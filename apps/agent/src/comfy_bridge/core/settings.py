from __future__ import annotations

import os
import secrets
from dataclasses import dataclass
from pathlib import Path


def _env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True, slots=True)
class Settings:
    host: str
    port: int
    comfy_url: str
    data_dir: Path
    workflow_dir: Path
    configured_token: str | None
    debug: bool
    max_upload_bytes: int = 20 * 1024 * 1024

    @classmethod
    def load(cls) -> Settings:
        file_path = Path(__file__).resolve()
        agent_dir = file_path.parents[3]
        repo_dir = file_path.parents[5]
        return cls(
            host=os.getenv("COMFY_BRIDGE_HOST", "0.0.0.0"),
            port=int(os.getenv("COMFY_BRIDGE_PORT", "8787")),
            comfy_url=os.getenv("COMFY_BRIDGE_COMFY_URL", "http://127.0.0.1:8188").rstrip("/"),
            data_dir=Path(os.getenv("COMFY_BRIDGE_DATA_DIR", str(agent_dir / "data"))).resolve(),
            workflow_dir=Path(
                os.getenv("COMFY_BRIDGE_WORKFLOW_DIR", str(repo_dir / "workflow-packs"))
            ).resolve(),
            configured_token=os.getenv("COMFY_BRIDGE_TOKEN"),
            debug=_env_bool("COMFY_BRIDGE_DEBUG"),
        )

    def ensure_directories(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        (self.data_dir / "assets").mkdir(parents=True, exist_ok=True)
        (self.data_dir / "media").mkdir(parents=True, exist_ok=True)
        self.workflow_dir.mkdir(parents=True, exist_ok=True)


def load_or_create_token(settings: Settings) -> tuple[str, bool]:
    """Return the configured/persisted token and whether a new one was created."""

    if settings.configured_token:
        return settings.configured_token, False

    token_file = settings.data_dir / "device-token.txt"
    if token_file.exists():
        token = token_file.read_text(encoding="utf-8").strip()
        if token:
            return token, False

    token = secrets.token_urlsafe(32)
    token_file.write_text(token + "\n", encoding="utf-8")
    return token, True
