from __future__ import annotations

import asyncio
import json
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from uuid import uuid4

import aiohttp

from comfy_bridge.core.errors import AppError, map_comfy_error

EventCallback = Callable[[str, dict[str, Any]], Awaitable[None]]


class ComfyUiClient:
    def __init__(self, base_url: str, *, debug: bool = False) -> None:
        self._base_url = base_url.rstrip("/")
        self._debug = debug
        self._session: aiohttp.ClientSession | None = None

    async def start(self) -> None:
        if self._session is None:
            timeout = aiohttp.ClientTimeout(total=None, connect=5, sock_connect=5)
            self._session = aiohttp.ClientSession(timeout=timeout)

    async def close(self) -> None:
        if self._session is not None:
            await self._session.close()
            self._session = None

    @property
    def session(self) -> aiohttp.ClientSession:
        if self._session is None:
            raise RuntimeError("ComfyUiClient.start() was not called")
        return self._session

    async def system_stats(self) -> dict[str, Any]:
        try:
            async with self.session.get(f"{self._base_url}/system_stats") as response:
                response.raise_for_status()
                payload = await response.json()
                return payload if isinstance(payload, dict) else {}
        except (TimeoutError, aiohttp.ClientError) as exc:
            raise AppError(
                "COMFY_OFFLINE",
                "ComfyUI 未启动或无法连接。",
                503,
                True,
                str(exc),
            ) from exc

    async def upload_asset(self, path: Path, mime_type: str) -> str:
        form = aiohttp.FormData()
        with path.open("rb") as handle:
            form.add_field(
                "image",
                handle,
                filename=path.name,
                content_type=mime_type,
            )
            form.add_field("type", "input")
            try:
                async with self.session.post(
                    f"{self._base_url}/upload/image", data=form
                ) as response:
                    payload = await self._read_json(response)
            except (TimeoutError, aiohttp.ClientError) as exc:
                raise AppError(
                    "ASSET_UPLOAD_FAILED", "素材上传到 ComfyUI 失败。", 502, True, str(exc)
                ) from exc
        name = payload.get("name")
        subfolder = payload.get("subfolder") or ""
        if not isinstance(name, str) or not name:
            raise AppError("ASSET_UPLOAD_FAILED", "ComfyUI 未返回有效的素材文件名。", 502)
        return f"{subfolder}/{name}" if subfolder else name

    async def execute(
        self,
        graph: dict[str, Any],
        callback: EventCallback,
        *,
        timeout_seconds: float = 21600,
    ) -> tuple[str, dict[str, Any]]:
        client_id = uuid4().hex
        ws_url = self._base_url.replace("http://", "ws://").replace("https://", "wss://")
        ws_url = f"{ws_url}/ws?{urlencode({'clientId': client_id})}"
        prompt_id: str | None = None
        try:
            async with self.session.ws_connect(ws_url, heartbeat=30) as socket:
                body = {"prompt": graph, "client_id": client_id}
                async with self.session.post(f"{self._base_url}/prompt", json=body) as response:
                    payload = await self._read_json(response)
                node_errors = payload.get("node_errors")
                if isinstance(node_errors, dict) and node_errors:
                    raise AppError(
                        "COMFY_PROMPT_INVALID",
                        "ComfyUI 检查工作流参数时发现错误。",
                        502,
                        False,
                        json.dumps(node_errors, ensure_ascii=False)[:8000],
                    )
                raw_prompt_id = payload.get("prompt_id")
                if not isinstance(raw_prompt_id, str) or not raw_prompt_id:
                    raise AppError("COMFY_INVALID_RESPONSE", "ComfyUI 未返回任务编号。", 502)
                prompt_id = raw_prompt_id
                await callback("prompt_submitted", {"prompt_id": prompt_id})

                completed = False
                async with asyncio.timeout(timeout_seconds):
                    async for message in socket:
                        if message.type == aiohttp.WSMsgType.BINARY:
                            continue
                        if message.type != aiohttp.WSMsgType.TEXT:
                            if message.type in {
                                aiohttp.WSMsgType.CLOSE,
                                aiohttp.WSMsgType.CLOSED,
                                aiohttp.WSMsgType.ERROR,
                            }:
                                break
                            continue
                        event = json.loads(message.data)
                        data = event.get("data") or {}
                        event_prompt_id = data.get("prompt_id")
                        if event_prompt_id and event_prompt_id != prompt_id:
                            continue
                        event_type = event.get("type")
                        if isinstance(event_type, str):
                            await callback(event_type, data)
                        if event_type == "execution_error":
                            detail = data.get("exception_message") or data.get("exception_type")
                            raise map_comfy_error(
                                str(detail or "Unknown execution error"), debug=self._debug
                            )
                        if event_type == "execution_interrupted":
                            raise AppError("TASK_INTERRUPTED", "任务已被中止。", 409)
                        if event_type == "execution_success" or (
                            event_type == "executing" and data.get("node") is None
                        ):
                            completed = True
                            break
                if not completed:
                    history = await self.get_history(prompt_id)
                    if not history:
                        raise AppError(
                            "COMFY_CONNECTION_LOST",
                            "与 ComfyUI 的实时连接中断。",
                            502,
                            True,
                        )
                return prompt_id, await self.get_history(prompt_id)
        except TimeoutError as exc:
            raise AppError("TASK_TIMEOUT", "任务执行超时。", 504, True) from exc
        except AppError:
            raise
        except (aiohttp.ClientError, json.JSONDecodeError) as exc:
            if prompt_id:
                try:
                    history = await self.get_history(prompt_id)
                    if history:
                        return prompt_id, history
                except AppError:
                    pass
            raise AppError(
                "COMFY_CONNECTION_LOST",
                "与 ComfyUI 的连接中断。",
                502,
                True,
                str(exc),
            ) from exc

    async def get_history(self, prompt_id: str) -> dict[str, Any]:
        try:
            async with self.session.get(f"{self._base_url}/history/{prompt_id}") as response:
                payload = await self._read_json(response)
        except (TimeoutError, aiohttp.ClientError) as exc:
            raise AppError(
                "HISTORY_UNAVAILABLE", "暂时无法读取生成结果。", 502, True, str(exc)
            ) from exc
        entry = payload.get(prompt_id)
        return entry if isinstance(entry, dict) else {}

    async def download_file(self, reference: dict[str, Any], target: Path) -> None:
        filename = reference.get("filename") or reference.get("name")
        if not isinstance(filename, str) or not filename:
            raise AppError("OUTPUT_INVALID", "生成结果缺少文件名。", 502)
        query = urlencode(
            {
                "filename": filename,
                "subfolder": reference.get("subfolder") or "",
                "type": reference.get("type") or "output",
            }
        )
        try:
            async with self.session.get(f"{self._base_url}/view?{query}") as response:
                if response.status >= 400:
                    await self._read_json(response)
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open("wb") as handle:
                    async for chunk in response.content.iter_chunked(1024 * 256):
                        handle.write(chunk)
        except (TimeoutError, aiohttp.ClientError) as exc:
            raise AppError(
                "OUTPUT_DOWNLOAD_FAILED", "生成结果下载失败。", 502, True, str(exc)
            ) from exc

    @staticmethod
    async def _read_json(response: aiohttp.ClientResponse) -> dict[str, Any]:
        if response.status >= 400:
            body = await response.text()
            raise AppError(
                "COMFY_HTTP_ERROR",
                "ComfyUI 拒绝了请求。",
                502,
                False,
                f"HTTP {response.status}: {body[:2000]}",
            )
        try:
            payload = await response.json()
        except (json.JSONDecodeError, aiohttp.ContentTypeError) as exc:
            raise AppError("COMFY_INVALID_RESPONSE", "ComfyUI 返回了无效响应。", 502) from exc
        return payload if isinstance(payload, dict) else {}
