from __future__ import annotations

import os
import subprocess
import sys
import threading
from collections.abc import Callable
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

from comfy_bridge.desktop.config import DesktopConfig, repository_root

LogCallback = Callable[[str, str], None]


class ServiceManager:
    def __init__(self, on_log: LogCallback) -> None:
        self._on_log = on_log
        self.agent_process: subprocess.Popen[str] | None = None
        self.frp_process: subprocess.Popen[str] | None = None
        self._lock = threading.Lock()

    @property
    def agent_running(self) -> bool:
        return self.agent_process is not None and self.agent_process.poll() is None

    @property
    def frp_running(self) -> bool:
        return self.frp_process is not None and self.frp_process.poll() is None

    def start_agent(self, config: DesktopConfig) -> None:
        with self._lock:
            if self.agent_running:
                self._on_log("bridge", "Bridge 已经在运行。")
                return
            if _endpoint_online(config.local_agent_url + "/health"):
                self._on_log("bridge", "检测到 Bridge 已由其他方式启动，本次不重复启动。")
                return
            env = os.environ.copy()
            env.update(
                {
                    "COMFY_BRIDGE_HOST": config.host.strip(),
                    "COMFY_BRIDGE_PORT": str(config.port),
                    "COMFY_BRIDGE_COMFY_URL": config.comfy_url.strip().rstrip("/"),
                    "COMFY_BRIDGE_DATA_DIR": str(Path(config.data_dir).resolve()),
                    "COMFY_BRIDGE_WORKFLOW_DIR": str(Path(config.workflow_dir).resolve()),
                    "COMFY_BRIDGE_DEBUG": "1" if config.debug else "0",
                    "PYTHONUTF8": "1",
                }
            )
            self.agent_process = self._start_process(
                [sys.executable, "-m", "comfy_bridge"],
                repository_root() / "apps" / "agent",
                env,
                "bridge",
            )
            self._on_log("bridge", f"Bridge 正在启动，端口 {config.port}。")

    def start_frp(self, config: DesktopConfig) -> None:
        with self._lock:
            if not config.frp_enabled:
                raise ValueError("请先在配置页启用 FRP。")
            if self.frp_running:
                self._on_log("frp", "FRP 已经在运行。")
                return
            public_url = config.resolved_public_url
            if public_url and _endpoint_online(public_url + "/health"):
                self._on_log("frp", "检测到公网入口已经在线，本次不重复启动 FRP。")
                return
            config.write_frp_config()
            executable = Path(config.frp_executable).resolve()
            config_path = Path(config.frp_config_path).resolve()
            if not executable.is_file():
                raise FileNotFoundError(f"找不到 FRP 客户端：{executable}")
            validation = subprocess.run(
                [str(executable), "verify", "-c", str(config_path)],
                cwd=config_path.parent,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=15,
                check=False,
            )
            if validation.returncode != 0:
                detail = (validation.stderr or validation.stdout).strip()
                raise RuntimeError(f"FRP 配置验证失败：{detail}")
            self.frp_process = self._start_process(
                [str(executable), "-c", str(config_path)],
                config_path.parent,
                os.environ.copy(),
                "frp",
            )
            self._on_log(
                "frp",
                f"FRP 正在启动：公网 {config.frp_remote_port} → 本机 {config.port}。",
            )

    def start_all(self, config: DesktopConfig) -> None:
        self.start_agent(config)
        if not config.frp_enabled:
            return
        try:
            self.start_frp(config)
        except Exception:
            self.stop_agent()
            raise

    def stop_agent(self) -> None:
        with self._lock:
            self._stop_process(self.agent_process, "bridge")
            self.agent_process = None

    def stop_frp(self) -> None:
        with self._lock:
            self._stop_process(self.frp_process, "frp")
            self.frp_process = None

    def stop_all(self) -> None:
        self.stop_frp()
        self.stop_agent()

    def _start_process(
        self,
        command: list[str],
        cwd: Path,
        env: dict[str, str],
        channel: str,
    ) -> subprocess.Popen[str]:
        creation_flags = 0
        if sys.platform == "win32":
            creation_flags = subprocess.CREATE_NO_WINDOW
        process = subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            creationflags=creation_flags,
        )
        thread = threading.Thread(
            target=self._pump_output,
            args=(process, channel),
            daemon=True,
            name=f"{channel}-output",
        )
        thread.start()
        return process

    def _pump_output(self, process: subprocess.Popen[str], channel: str) -> None:
        if process.stdout is None:
            return
        for line in process.stdout:
            clean_line = line.rstrip()
            if clean_line:
                self._on_log(channel, clean_line)
        return_code = process.wait()
        self._on_log(channel, f"进程已结束，退出码 {return_code}。")

    def _stop_process(self, process: subprocess.Popen[str] | None, channel: str) -> None:
        if process is None or process.poll() is not None:
            return
        self._on_log(channel, "正在停止服务…")
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        self._on_log(channel, "服务已停止。")


def _endpoint_online(url: str) -> bool:
    try:
        with urlopen(url, timeout=2) as response:
            status = int(response.status)
            return 200 <= status < 300
    except (HTTPError, URLError, TimeoutError, OSError):
        return False
