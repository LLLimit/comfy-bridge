from __future__ import annotations

import asyncio
import hashlib
import math
import mimetypes
import struct
import zlib
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from comfy_bridge.application.event_bus import EventBus
from comfy_bridge.application.workflow_patcher import WorkflowPatcher
from comfy_bridge.application.workflow_registry import WorkflowRegistry
from comfy_bridge.core.errors import AppError
from comfy_bridge.domain.models import (
    CreateTaskRequest,
    TaskError,
    TaskOutput,
    TaskProgress,
    TaskSnapshot,
    TaskStatus,
    WorkflowConfig,
)
from comfy_bridge.infrastructure.comfyui.client import ComfyUiClient
from comfy_bridge.infrastructure.persistence.store import MediaRecord, Store


class TaskService:
    def __init__(
        self,
        store: Store,
        registry: WorkflowRegistry,
        patcher: WorkflowPatcher,
        comfy: ComfyUiClient,
        events: EventBus,
        media_dir: Path,
        *,
        debug: bool = False,
    ) -> None:
        self._store = store
        self._registry = registry
        self._patcher = patcher
        self._comfy = comfy
        self._events = events
        self._media_dir = media_dir
        self._debug = debug
        self._workers: dict[UUID, asyncio.Task[None]] = {}

    async def shutdown(self) -> None:
        workers = tuple(self._workers.values())
        for worker in workers:
            worker.cancel()
        if workers:
            await asyncio.gather(*workers, return_exceptions=True)

    async def create(self, request: CreateTaskRequest) -> TaskSnapshot:
        existing = self._store.get_task_by_client_request(request.client_request_id)
        if existing:
            return existing
        config = self._registry.get(request.workflow_id)
        if config.revision != request.workflow_revision:
            raise AppError(
                "WORKFLOW_REVISION_CHANGED",
                "生成模式已经更新，请刷新页面后重试。",
                409,
            )
        values = self._patcher.validate_values(config, request.inputs)
        task = TaskSnapshot(
            client_request_id=request.client_request_id,
            workflow_id=config.id,
            workflow_revision=config.revision,
            workflow_name=config.name,
            category=config.category,
            inputs=values,
        )
        self._store.save_task(task)
        await self._events.publish_task("task.created", task)
        worker = asyncio.create_task(self._run(task.id), name=f"task-{task.id}")
        self._workers[task.id] = worker
        worker.add_done_callback(lambda _: self._workers.pop(task.id, None))
        return task

    def get(self, task_id: UUID) -> TaskSnapshot:
        task = self._store.get_task(task_id)
        if not task:
            raise AppError("TASK_NOT_FOUND", "找不到这个任务。", 404)
        return task

    def list_tasks(self, limit: int = 100) -> list[TaskSnapshot]:
        return self._store.list_tasks(limit)

    async def delete(self, task_id: UUID) -> None:
        self.get(task_id)
        worker = self._workers.pop(task_id, None)
        if worker is not None and not worker.done():
            worker.cancel()
            await asyncio.gather(worker, return_exceptions=True)
        for media in self._store.list_media_for_task(task_id):
            try:
                media.path.unlink(missing_ok=True)
            except OSError as exc:
                raise AppError(
                    "TASK_DELETE_FAILED",
                    "任务文件删除失败，请查看 Agent 日志。",
                    500,
                    technical_detail=str(exc),
                ) from exc
        self._store.delete_task(task_id)
        await self._events.publish("task.deleted", task_id, {"id": str(task_id)})

    async def delete_output(self, media_id: UUID) -> None:
        media = self._store.get_media(media_id)
        if media is None:
            raise AppError("MEDIA_NOT_FOUND", "找不到这个作品文件。", 404)
        task = self.get(media.task_id)
        try:
            media.path.unlink(missing_ok=True)
        except OSError as exc:
            raise AppError(
                "MEDIA_DELETE_FAILED",
                "作品文件删除失败，请查看 Agent 日志。",
                500,
                technical_detail=str(exc),
            ) from exc
        self._store.delete_media(media_id)
        task.outputs = [output for output in task.outputs if output.id != media_id]
        await self._update(
            task,
            status=task.status,
            progress=task.progress,
        )

    async def _run(self, task_id: UUID) -> None:
        task = self.get(task_id)
        config = self._registry.get(task.workflow_id)
        try:
            if config.provider == "mock":
                await self._run_mock(task, config)
            else:
                await self._run_comfy(task, config)
        except asyncio.CancelledError:
            await self._update(
                task,
                status=TaskStatus.CANCELLED,
                progress=TaskProgress(stage="任务已取消"),
            )
            raise
        except AppError as exc:
            payload = exc.public_payload()
            await self._update(
                task,
                status=TaskStatus.FAILED,
                progress=TaskProgress(stage="生成失败"),
                error=TaskError.model_validate(payload),
                event_type="task.failed",
            )
        except Exception as exc:  # defensive boundary around background work
            detail = str(exc) if self._debug else None
            await self._update(
                task,
                status=TaskStatus.FAILED,
                progress=TaskProgress(stage="生成失败"),
                error=TaskError(
                    code="UNEXPECTED_ERROR",
                    message="任务执行失败，请查看 Agent 日志。",
                    debug_id=detail,
                ),
                event_type="task.failed",
            )

    async def _run_mock(self, task: TaskSnapshot, config: WorkflowConfig) -> None:
        stages = [
            (TaskStatus.QUEUED, "任务已提交"),
            (TaskStatus.RUNNING, "正在加载演示模型"),
        ]
        for status, label in stages:
            await self._update(
                task,
                status=status,
                progress=TaskProgress(stage=label, indeterminate=True),
            )
            await asyncio.sleep(0.35)

        for value in range(0, 11):
            await self._update(
                task,
                status=TaskStatus.RUNNING,
                progress=TaskProgress(
                    stage="正在生成演示图片",
                    value=value,
                    maximum=10,
                    percent=float(value * 10),
                ),
            )
            await asyncio.sleep(0.12)

        await self._update(
            task,
            status=TaskStatus.PROCESSING,
            progress=TaskProgress(stage="正在处理输出", indeterminate=True),
        )
        media_id = uuid4()
        path = self._media_dir / f"{media_id}.png"
        width = int(task.inputs.get("width") or 768)
        height = int(task.inputs.get("height") or 512)
        prompt = str(task.inputs.get("prompt") or "Comfy Bridge")
        self._write_demo_png(path, prompt, width, height)
        media = MediaRecord(media_id, task.id, path, "image/png")
        self._store.save_media(media)
        output = TaskOutput(
            id=media_id,
            key=config.outputs[0].key,
            media_type="image",
            mime_type="image/png",
            file_name=path.name,
            url=f"/api/v1/media/{media_id}",
        )
        task.outputs = [output]
        task.completed_at = datetime.now(UTC)
        await self._update(
            task,
            status=TaskStatus.COMPLETED,
            progress=TaskProgress(stage="生成完成", value=1, maximum=1, percent=100),
            event_type="task.completed",
        )

    async def _run_comfy(self, task: TaskSnapshot, config: WorkflowConfig) -> None:
        graph = self._registry.load_graph(config.id)
        uploaded: dict[str, str] = {}
        asset_inputs = [item for item in config.inputs if item.value_type == "asset"]
        if asset_inputs:
            await self._update(
                task,
                status=TaskStatus.UPLOADING,
                progress=TaskProgress(stage="正在上传参考素材", indeterminate=True),
            )
        for definition in asset_inputs:
            value = task.inputs.get(definition.key)
            if not value:
                continue
            try:
                asset_id = UUID(str(value))
            except ValueError as exc:
                raise AppError("ASSET_INVALID", "参考素材编号无效。") from exc
            asset = self._store.get_asset(asset_id)
            if not asset or not asset.path.exists():
                raise AppError("ASSET_NOT_FOUND", "找不到上传的参考素材。", 404)
            uploaded[definition.key] = await self._comfy.upload_asset(asset.path, asset.mime_type)

        patched = self._patcher.patch(config, graph, task.inputs, uploaded)
        stages = {stage.node_id: stage.label for stage in config.stages}

        async def on_event(event_type: str, data: dict[str, Any]) -> None:
            if event_type == "prompt_submitted":
                task.prompt_id = str(data["prompt_id"])
                await self._update(
                    task,
                    status=TaskStatus.QUEUED,
                    progress=TaskProgress(stage="任务已提交", indeterminate=True),
                )
            elif event_type == "execution_start":
                await self._update(
                    task,
                    status=TaskStatus.RUNNING,
                    progress=TaskProgress(stage="工作流已开始", indeterminate=True),
                )
            elif event_type == "executing" and data.get("node") is not None:
                node_id = str(data["node"])
                await self._update(
                    task,
                    status=TaskStatus.RUNNING,
                    progress=TaskProgress(
                        stage=stages.get(node_id, "正在执行工作流"), indeterminate=True
                    ),
                )
            elif event_type == "progress":
                value = int(data.get("value") or 0)
                maximum = int(data.get("max") or 0)
                percent = value / maximum * 100 if maximum > 0 else None
                await self._update(
                    task,
                    status=TaskStatus.RUNNING,
                    progress=TaskProgress(
                        stage="生成中",
                        value=value,
                        maximum=maximum or None,
                        percent=percent,
                        indeterminate=maximum <= 0,
                    ),
                )

        prompt_id, history = await self._comfy.execute(patched, on_event)
        task.prompt_id = prompt_id
        await self._update(
            task,
            status=TaskStatus.PROCESSING,
            progress=TaskProgress(stage="正在读取生成结果", indeterminate=True),
        )
        outputs = await self._collect_outputs(task, config, history)
        if not outputs:
            raise AppError("OUTPUT_NOT_FOUND", "任务已结束，但没有找到生成结果。", 502)
        task.outputs = outputs
        task.completed_at = datetime.now(UTC)
        await self._update(
            task,
            status=TaskStatus.COMPLETED,
            progress=TaskProgress(stage="生成完成", value=1, maximum=1, percent=100),
            event_type="task.completed",
        )

    async def _collect_outputs(
        self,
        task: TaskSnapshot,
        config: WorkflowConfig,
        history: dict[str, Any],
    ) -> list[TaskOutput]:
        history_outputs = history.get("outputs") or {}
        collected: list[TaskOutput] = []
        for definition in config.outputs:
            if not definition.is_enabled(task.inputs):
                continue
            node_output = history_outputs.get(definition.node_id or "") or {}
            references = node_output.get(definition.history_field or "") or []
            if not isinstance(references, list):
                continue
            for reference in references:
                if not isinstance(reference, dict):
                    continue
                source_name = str(reference.get("filename") or reference.get("name") or "output")
                suffix = Path(source_name).suffix.lower() or (
                    ".png" if definition.media_type == "image" else ".mp4"
                )
                media_id = uuid4()
                target = self._media_dir / f"{media_id}{suffix}"
                await self._comfy.download_file(reference, target)
                mime_type = mimetypes.guess_type(target.name)[0] or (
                    "image/png" if definition.media_type == "image" else "video/mp4"
                )
                self._store.save_media(MediaRecord(media_id, task.id, target, mime_type))
                collected.append(
                    TaskOutput(
                        id=media_id,
                        key=definition.key,
                        media_type=definition.media_type,
                        mime_type=mime_type,
                        file_name=source_name,
                        url=f"/api/v1/media/{media_id}",
                    )
                )
        return collected

    async def _update(
        self,
        task: TaskSnapshot,
        *,
        status: TaskStatus,
        progress: TaskProgress,
        error: TaskError | None = None,
        event_type: str = "task.updated",
    ) -> None:
        task.status = status
        task.progress = progress
        task.error = error
        task.updated_at = datetime.now(UTC)
        self._store.save_task(task)
        await self._events.publish_task(event_type, task)

    @staticmethod
    def _write_demo_png(path: Path, prompt: str, width: int, height: int) -> None:
        width = max(256, min(width, 1024))
        height = max(256, min(height, 1024))
        digest = hashlib.sha256(prompt.encode("utf-8")).digest()
        base = tuple(digest[index] for index in range(3))
        accent = tuple(digest[index] for index in range(3, 6))
        rows = bytearray()
        for y in range(height):
            rows.append(0)
            for x in range(width):
                wave = (math.sin(x / 47) + math.cos(y / 31) + 2) / 4
                radial = math.hypot(x - width / 2, y - height / 2) / max(width, height)
                blend = max(0.0, min(1.0, wave * 0.72 + radial * 0.28))
                rows.extend(
                    int(base[channel] * (1 - blend) + accent[channel] * blend)
                    for channel in range(3)
                )

        def chunk(kind: bytes, data: bytes) -> bytes:
            payload = kind + data
            return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload))

        png = bytearray(b"\x89PNG\r\n\x1a\n")
        png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        png.extend(chunk(b"IDAT", zlib.compress(bytes(rows), level=6)))
        png.extend(chunk(b"IEND", b""))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(png)
