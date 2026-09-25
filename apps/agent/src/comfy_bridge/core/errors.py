from __future__ import annotations

from dataclasses import dataclass
from uuid import uuid4


@dataclass(slots=True)
class AppError(Exception):
    code: str
    message: str
    status_code: int = 400
    retryable: bool = False
    technical_detail: str | None = None

    def __post_init__(self) -> None:
        super().__init__(self.message)

    def public_payload(self) -> dict[str, object]:
        return {
            "code": self.code,
            "message": self.message,
            "retryable": self.retryable,
            "debugId": str(uuid4()),
        }


def map_comfy_error(message: str, *, debug: bool = False) -> AppError:
    normalized = message.lower()
    if "out of memory" in normalized or "cuda" in normalized and "memory" in normalized:
        public = "显存不足，请降低分辨率、时长或批次数量后重试。"
        code = "COMFY_OUT_OF_MEMORY"
    elif "no such file" in normalized or "not found" in normalized:
        public = "工作流需要的模型或文件不存在。"
        code = "COMFY_FILE_NOT_FOUND"
    elif "node" in normalized and ("missing" in normalized or "unknown" in normalized):
        public = "工作流包含当前 ComfyUI 未安装的节点。"
        code = "COMFY_NODE_MISSING"
    else:
        public = "任务执行失败，请查看 Agent 日志后重试。"
        code = "COMFY_EXECUTION_FAILED"
    if debug:
        public = f"{public}（调试信息：{message}）"
    return AppError(code, public, 502, retryable=False, technical_detail=message)
