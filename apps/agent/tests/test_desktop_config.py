from __future__ import annotations

import json
import tomllib
from pathlib import Path

import pytest

from comfy_bridge.desktop.config import DesktopConfig


def _config(tmp_path: Path) -> DesktopConfig:
    return DesktopConfig(
        host="0.0.0.0",
        port=8787,
        comfy_url="http://127.0.0.1:8188",
        data_dir=str(tmp_path / "data"),
        workflow_dir=str(tmp_path / "workflows"),
        comfy_log_path="",
        debug=False,
        frp_enabled=True,
        frp_executable=str(tmp_path / "frpc.exe"),
        frp_config_path=str(tmp_path / "frp" / "frpc.toml"),
        frp_server_addr="frp.example.com",
        frp_server_port=7000,
        frp_auth_token="secret-frp-token",
        frp_remote_port=18188,
        frp_tls=True,
        frp_encryption=True,
        frp_compression=False,
        public_agent_url="https://agent.example.com",
    )


def test_desktop_config_writes_agent_frp_mapping_without_copying_secret_to_json(
    tmp_path: Path,
) -> None:
    config = _config(tmp_path)

    config.save()

    desktop_payload = json.loads(config.desktop_config_path.read_text(encoding="utf-8"))
    assert "frp_auth_token" not in desktop_payload
    frp_payload = tomllib.loads(Path(config.frp_config_path).read_text(encoding="utf-8"))
    assert frp_payload["auth"]["token"] == "secret-frp-token"
    assert frp_payload["proxies"][0]["localPort"] == 8787
    assert frp_payload["proxies"][0]["remotePort"] == 18188


def test_device_token_can_be_created_and_rotated(tmp_path: Path) -> None:
    config = _config(tmp_path)

    first = config.load_or_create_device_token()
    second = config.regenerate_device_token()

    assert first != second
    assert config.token_path.read_text(encoding="utf-8").strip() == second


def test_frp_fields_are_optional_when_frp_is_disabled(tmp_path: Path) -> None:
    config = _config(tmp_path)
    config.frp_enabled = False
    config.frp_server_addr = ""
    config.frp_auth_token = ""

    config.validate()


def test_invalid_port_is_rejected(tmp_path: Path) -> None:
    config = _config(tmp_path)
    config.port = 70000

    with pytest.raises(ValueError, match="Agent 端口"):
        config.validate()
