from __future__ import annotations

import hmac
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated, Any, cast
from uuid import UUID, uuid4

from fastapi import (
    Depends,
    FastAPI,
    File,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from comfy_bridge import __version__
from comfy_bridge.application.event_bus import EventBus
from comfy_bridge.application.task_service import TaskService
from comfy_bridge.application.workflow_patcher import WorkflowPatcher
from comfy_bridge.application.workflow_registry import WorkflowRegistry
from comfy_bridge.core.errors import AppError
from comfy_bridge.core.settings import Settings, load_or_create_token
from comfy_bridge.domain.models import AssetResponse, CreateTaskRequest, TaskSnapshot
from comfy_bridge.infrastructure.comfyui.client import ComfyUiClient
from comfy_bridge.infrastructure.persistence.store import AssetRecord, Store

LOGGER = logging.getLogger("comfy_bridge")
BEARER = HTTPBearer(auto_error=False)
ALLOWED_ASSET_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "audio/mpeg": ".mp3",
    "audio/wav": ".wav",
    "audio/mp4": ".m4a",
    "audio/flac": ".flac",
    "audio/ogg": ".ogg",
}
MIME_ALIASES = {
    "audio/x-wav": "audio/wav",
    "audio/x-m4a": "audio/mp4",
    "audio/x-flac": "audio/flac",
}


@dataclass(slots=True)
class AppContext:
    settings: Settings
    token: str
    store: Store
    registry: WorkflowRegistry
    comfy: ComfyUiClient
    events: EventBus
    tasks: TaskService


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or Settings.load()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        resolved_settings.ensure_directories()
        token, created = load_or_create_token(resolved_settings)
        store = Store(resolved_settings.data_dir / "agent.sqlite3")
        registry = WorkflowRegistry(resolved_settings.workflow_dir)
        comfy = ComfyUiClient(resolved_settings.comfy_url, debug=resolved_settings.debug)
        events = EventBus()
        tasks = TaskService(
            store,
            registry,
            WorkflowPatcher(),
            comfy,
            events,
            resolved_settings.data_dir / "media",
            debug=resolved_settings.debug,
        )
        await comfy.start()
        app.state.context = AppContext(
            resolved_settings, token, store, registry, comfy, events, tasks
        )
        if created:
            LOGGER.warning("New device token (shown once): %s", token)
        LOGGER.info(
            "Loaded %d workflow pack(s) from %s",
            len(registry.list_public()),
            resolved_settings.workflow_dir,
        )
        try:
            yield
        finally:
            await tasks.shutdown()
            await comfy.close()
            store.close()

    app = FastAPI(
        title="Comfy Bridge Agent",
        version=__version__,
        lifespan=lifespan,
    )

    @app.exception_handler(AppError)
    async def handle_app_error(_request: Request, error: AppError) -> JSONResponse:
        if error.technical_detail:
            LOGGER.error("%s: %s", error.code, error.technical_detail)
        return JSONResponse(
            status_code=error.status_code, content={"error": error.public_payload()}
        )

    @app.exception_handler(Exception)
    async def handle_unexpected(_request: Request, error: Exception) -> JSONResponse:
        LOGGER.exception("Unhandled API error", exc_info=error)
        payload = AppError(
            "INTERNAL_ERROR", "Agent 发生内部错误。", 500, False, str(error)
        ).public_payload()
        return JSONResponse(status_code=500, content={"error": payload})

    def context(request: Request) -> AppContext:
        return cast(AppContext, request.app.state.context)

    async def authenticate(
        request: Request,
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(BEARER)],
    ) -> None:
        expected = context(request).token
        if (
            credentials is None
            or credentials.scheme.lower() != "bearer"
            or not hmac.compare_digest(credentials.credentials, expected)
        ):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")

    secured = Depends(authenticate)

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok", "version": __version__}

    @app.get("/api/v1/status", dependencies=[secured])
    async def get_status(request: Request) -> dict[str, Any]:
        app_context = context(request)
        comfy_online = True
        stats: dict[str, Any] = {}
        try:
            stats = await app_context.comfy.system_stats()
        except AppError:
            comfy_online = False
        raw_system = stats.get("system")
        system = cast(dict[str, Any], raw_system) if isinstance(raw_system, dict) else {}
        raw_devices = stats.get("devices", system.get("devices"))
        devices = raw_devices if isinstance(raw_devices, list) else []
        gpu = devices[0] if devices else None
        active_count = sum(
            task.status.value in {"pending", "uploading", "queued", "running", "processing"}
            for task in app_context.tasks.list_tasks()
        )
        return {
            "agent": {"online": True, "version": __version__},
            "comfyUi": {
                "online": comfy_online,
                "url": app_context.settings.comfy_url,
            },
            "gpu": gpu,
            "activeTasks": active_count,
        }

    @app.get("/api/v1/workflows", dependencies=[secured])
    async def list_workflows(request: Request) -> dict[str, Any]:
        return {"items": context(request).registry.list_public()}

    @app.get("/api/v1/workflows/{workflow_id}", dependencies=[secured])
    async def get_workflow(workflow_id: str, request: Request) -> dict[str, Any]:
        return context(request).registry.get(workflow_id).public_manifest()

    @app.get("/api/v1/logs", dependencies=[secured])
    async def get_logs(
        request: Request,
        limit: Annotated[int, Query(ge=1, le=500)] = 200,
    ) -> dict[str, list[str]]:
        log_path = context(request).settings.data_dir / "agent.log"
        if not log_path.exists():
            return {"items": []}
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        return {"items": lines[-limit:]}

    @app.post(
        "/api/v1/assets",
        response_model=AssetResponse,
        status_code=status.HTTP_201_CREATED,
        dependencies=[secured],
    )
    async def upload_asset(request: Request, file: Annotated[UploadFile, File()]) -> AssetResponse:
        app_context = context(request)
        declared_type = MIME_ALIASES.get(
            (file.content_type or "").lower(), (file.content_type or "").lower()
        )
        content = await file.read(app_context.settings.max_upload_bytes + 1)
        if len(content) > app_context.settings.max_upload_bytes:
            raise AppError("FILE_TOO_LARGE", "单个素材大小不能超过 20 MB。", 413)
        detected_type = _detect_asset_type(content)
        if detected_type not in ALLOWED_ASSET_TYPES:
            raise AppError("UNSUPPORTED_FILE_TYPE", "仅支持常用图片或音频格式。", 415)
        declared_family = declared_type.partition("/")[0]
        detected_family = detected_type.partition("/")[0]
        if declared_type in ALLOWED_ASSET_TYPES and declared_family != detected_family:
            raise AppError("FILE_CONTENT_MISMATCH", "素材内容与文件类型不匹配。", 415)
        asset_id = uuid4()
        path = (
            app_context.settings.data_dir
            / "assets"
            / f"{asset_id}{ALLOWED_ASSET_TYPES[detected_type]}"
        )
        path.write_bytes(content)
        record = AssetRecord(
            asset_id,
            path,
            Path(file.filename or "upload").name,
            detected_type,
            len(content),
        )
        app_context.store.save_asset(record)
        return AssetResponse(
            id=asset_id,
            file_name=record.original_name,
            mime_type=record.mime_type,
            size=record.size,
        )

    @app.post(
        "/api/v1/tasks",
        response_model=TaskSnapshot,
        status_code=status.HTTP_202_ACCEPTED,
        dependencies=[secured],
    )
    async def create_task(body: CreateTaskRequest, request: Request) -> TaskSnapshot:
        return await context(request).tasks.create(body)

    @app.get("/api/v1/tasks", dependencies=[secured])
    async def list_tasks(
        request: Request,
        limit: Annotated[int, Query(ge=1, le=200)] = 100,
    ) -> dict[str, Any]:
        tasks = context(request).tasks.list_tasks(limit)
        return {"items": [task.model_dump(by_alias=True, mode="json") for task in tasks]}

    @app.get(
        "/api/v1/tasks/{task_id}",
        response_model=TaskSnapshot,
        dependencies=[secured],
    )
    async def get_task(task_id: UUID, request: Request) -> TaskSnapshot:
        return context(request).tasks.get(task_id)

    @app.delete(
        "/api/v1/tasks/{task_id}",
        status_code=status.HTTP_204_NO_CONTENT,
        dependencies=[secured],
    )
    async def delete_task(task_id: UUID, request: Request) -> Response:
        await context(request).tasks.delete(task_id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.get("/api/v1/media/{media_id}", dependencies=[secured])
    async def get_media(media_id: UUID, request: Request) -> FileResponse:
        media = context(request).store.get_media(media_id)
        if not media or not media.path.exists():
            raise AppError("MEDIA_NOT_FOUND", "找不到这个作品文件。", 404)
        return FileResponse(
            media.path,
            media_type=media.mime_type,
            filename=media.path.name,
            content_disposition_type="inline",
        )

    @app.delete(
        "/api/v1/media/{media_id}",
        status_code=status.HTTP_204_NO_CONTENT,
        dependencies=[secured],
    )
    async def delete_media(media_id: UUID, request: Request) -> Response:
        await context(request).tasks.delete_output(media_id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.websocket("/api/v1/events")
    async def websocket_events(websocket: WebSocket, token: str = Query(default="")) -> None:
        app_context: AppContext = websocket.app.state.context
        if not hmac.compare_digest(token, app_context.token):
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return
        await websocket.accept()
        snapshots = [
            item.model_dump(by_alias=True, mode="json") for item in app_context.tasks.list_tasks()
        ]
        await websocket.send_json(
            {
                "schemaVersion": 1,
                "eventId": str(uuid4()),
                "sequence": 0,
                "type": "agent.snapshot",
                "taskId": None,
                "occurredAt": datetime.now(UTC).isoformat(),
                "payload": {"tasks": snapshots},
            }
        )
        try:
            async with app_context.events.subscribe() as queue:
                while True:
                    event = await queue.get()
                    await websocket.send_text(event.model_dump_json(by_alias=True))
        except WebSocketDisconnect:
            return

    return app


def _detect_asset_type(content: bytes) -> str | None:
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if content.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if len(content) >= 12 and content[:4] == b"RIFF" and content[8:12] == b"WEBP":
        return "image/webp"
    if len(content) >= 12 and content[:4] == b"RIFF" and content[8:12] == b"WAVE":
        return "audio/wav"
    if content.startswith(b"ID3") or (
        len(content) >= 2 and content[0] == 0xFF and content[1] & 0xE0 == 0xE0
    ):
        return "audio/mpeg"
    if len(content) >= 12 and content[4:8] == b"ftyp":
        return "audio/mp4"
    if content.startswith(b"fLaC"):
        return "audio/flac"
    if content.startswith(b"OggS"):
        return "audio/ogg"
    return None
