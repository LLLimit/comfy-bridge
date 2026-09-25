from __future__ import annotations

import json
import secrets
import tomllib
from dataclasses import asdict, dataclass, fields
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


def repository_root() -> Path:
    return Path(__file__).resolve().parents[5]


@dataclass(slots=True)
class DesktopConfig:
    host: str
    port: int
    comfy_url: str
    data_dir: str
    workflow_dir: str
    comfy_log_path: str
    debug: bool
    frp_enabled: bool
    frp_executable: str
    frp_config_path: str
    frp_server_addr: str
    frp_server_port: int
    frp_auth_token: str
    frp_remote_port: int
    frp_tls: bool
    frp_encryption: bool
    frp_compression: bool
    public_agent_url: str

    @classmethod
    def defaults(cls) -> DesktopConfig:
        root = repository_root()
        return cls(
            host="0.0.0.0",
            port=8787,
            comfy_url="http://127.0.0.1:8188",
            data_dir=str(root / "apps" / "agent" / "data"),
            workflow_dir=str(root / "workflow-packs"),
            comfy_log_path="",
            debug=False,
            frp_enabled=False,
            frp_executable=str(root / ".tooling" / "frp" / "frpc.exe"),
            frp_config_path=str(root / ".tooling" / "frp" / "frpc.toml"),
            frp_server_addr="",
            frp_server_port=7000,
            frp_auth_token="",
            frp_remote_port=18188,
            frp_tls=True,
            frp_encryption=True,
            frp_compression=False,
            public_agent_url="",
        )

    @classmethod
    def load(cls) -> DesktopConfig:
        config = cls.defaults()
        config._import_frp_config()
        path = config.desktop_config_path
        if not path.exists():
            return config
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return config
        if not isinstance(raw, dict):
            return config
        valid_names = {item.name for item in fields(config)} - {"frp_auth_token"}
        for name, value in raw.items():
            if name in valid_names:
                setattr(config, name, value)
        config._import_frp_config()
        return config

    @property
    def desktop_config_path(self) -> Path:
        return Path(self.data_dir).resolve() / "desktop-settings.json"

    @property
    def token_path(self) -> Path:
        return Path(self.data_dir).resolve() / "device-token.txt"

    @property
    def agent_log_path(self) -> Path:
        return Path(self.data_dir).resolve() / "agent.log"

    @property
    def frp_log_path(self) -> Path:
        return Path(self.frp_config_path).resolve().with_name("frpc.log")

    @property
    def local_agent_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    @property
    def resolved_public_url(self) -> str:
        if self.public_agent_url.strip():
            return self.public_agent_url.strip().rstrip("/")
        if self.frp_server_addr.strip():
            return f"http://{self.frp_server_addr.strip()}:{self.frp_remote_port}"
        return ""

    def save(self) -> None:
        self.validate()
        path = self.desktop_config_path
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = asdict(self)
        payload.pop("frp_auth_token", None)
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        if self.frp_enabled:
            self.write_frp_config()

    def validate(self) -> None:
        if not self.host.strip():
            raise ValueError("Agent 监听地址不能为空。")
        _validate_port(self.port, "Agent 端口")
        _validate_http_url(self.comfy_url, "ComfyUI 地址")
        if not self.data_dir.strip():
            raise ValueError("数据目录不能为空。")
        if not self.workflow_dir.strip():
            raise ValueError("工作流目录不能为空。")
        if self.frp_enabled:
            if not self.frp_server_addr.strip():
                raise ValueError("FRP 服务器地址不能为空。")
            _validate_port(self.frp_server_port, "FRP 控制端口")
            _validate_port(self.frp_remote_port, "FRP 公网端口")
            if not self.frp_auth_token.strip():
                raise ValueError("FRP 验证 Token 不能为空。")
            if self.public_agent_url.strip():
                _validate_http_url(self.public_agent_url, "公网 Agent 地址")

    def load_or_create_device_token(self) -> str:
        path = self.token_path
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            token = path.read_text(encoding="utf-8").strip()
            if token:
                return token
        return self.regenerate_device_token()

    def regenerate_device_token(self) -> str:
        token = secrets.token_urlsafe(32)
        path = self.token_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(token + "\n", encoding="utf-8")
        return token

    def write_frp_config(self) -> None:
        path = Path(self.frp_config_path).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        log_path = path.with_name("frpc.log")
        text = "\n".join(
            [
                f"serverAddr = {_toml_string(self.frp_server_addr.strip())}",
                f"serverPort = {self.frp_server_port}",
                "",
                'auth.method = "token"',
                f"auth.token = {_toml_string(self.frp_auth_token.strip())}",
                "",
                f"transport.tls.enable = {_toml_bool(self.frp_tls)}",
                "",
                f"log.to = {_toml_string(str(log_path))}",
                'log.level = "info"',
                "log.maxDays = 7",
                "",
                "[[proxies]]",
                'name = "windows-agent"',
                'type = "tcp"',
                'localIP = "127.0.0.1"',
                f"localPort = {self.port}",
                f"remotePort = {self.frp_remote_port}",
                "",
                f"transport.useEncryption = {_toml_bool(self.frp_encryption)}",
                f"transport.useCompression = {_toml_bool(self.frp_compression)}",
                "",
                'healthCheck.type = "tcp"',
                "healthCheck.timeoutSeconds = 3",
                "healthCheck.maxFailed = 3",
                "healthCheck.intervalSeconds = 10",
                "",
            ]
        )
        path.write_text(text, encoding="utf-8")

    def _import_frp_config(self) -> None:
        path = Path(self.frp_config_path)
        if not path.exists():
            return
        try:
            raw = tomllib.loads(path.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError):
            return
        self.frp_enabled = True
        self.frp_server_addr = str(raw.get("serverAddr", self.frp_server_addr))
        self.frp_server_port = _as_int(raw.get("serverPort"), self.frp_server_port)
        auth = raw.get("auth")
        if isinstance(auth, dict):
            self.frp_auth_token = str(auth.get("token", self.frp_auth_token))
        transport = raw.get("transport")
        if isinstance(transport, dict):
            tls = transport.get("tls")
            if isinstance(tls, dict):
                self.frp_tls = bool(tls.get("enable", self.frp_tls))
        proxies = raw.get("proxies")
        if isinstance(proxies, list) and proxies and isinstance(proxies[0], dict):
            proxy: dict[str, Any] = proxies[0]
            self.frp_remote_port = _as_int(proxy.get("remotePort"), self.frp_remote_port)
            proxy_transport = proxy.get("transport")
            if isinstance(proxy_transport, dict):
                self.frp_encryption = bool(
                    proxy_transport.get("useEncryption", self.frp_encryption)
                )
                self.frp_compression = bool(
                    proxy_transport.get("useCompression", self.frp_compression)
                )


def _as_int(value: object, default: int) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else default


def _validate_port(value: int, label: str) -> None:
    if not 1 <= value <= 65535:
        raise ValueError(f"{label}必须在 1–65535 之间。")


def _validate_http_url(value: str, label: str) -> None:
    parsed = urlparse(value.strip())
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError(f"{label}必须是完整的 http:// 或 https:// 地址。")


def _toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _toml_bool(value: bool) -> str:
    return "true" if value else "false"
