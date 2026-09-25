from __future__ import annotations

import json
import threading
from collections.abc import Callable
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from PySide6.QtCore import Property, QObject, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QApplication, QFileDialog, QMessageBox

from comfy_bridge.desktop.config import DesktopConfig
from comfy_bridge.desktop.services import ServiceManager


class DesktopBackend(QObject):
    configChanged = Signal()
    statusChanged = Signal()
    checkingChanged = Signal()
    summaryChanged = Signal()
    tokenChanged = Signal()
    logsChanged = Signal()
    toastRequested = Signal(str, str)
    _statusReady = Signal(object)
    _logsReady = Signal(object)
    _serviceFinished = Signal(str, str)
    _processLog = Signal(str, str)

    def __init__(self) -> None:
        super().__init__()
        self.config = DesktopConfig.load()
        self.manager = ServiceManager(self._receive_process_log)
        self._refreshing = False
        self._checking = False
        self._summary = "等待检测"
        self._token = self.config.load_or_create_device_token()
        self._status: dict[str, dict[str, object]] = {
            key: {"label": "等待检测", "online": False, "tone": "muted"}
            for key in ("agent", "comfy", "frp", "public")
        }
        self._logs: dict[str, str] = {
            "comfy": "正在读取日志…",
            "bridge": "正在读取日志…",
            "frp": "正在读取日志…",
        }
        self._statusReady.connect(self._apply_status)
        self._logsReady.connect(self._apply_logs)
        self._serviceFinished.connect(self._handle_service_finished)
        self._processLog.connect(self._append_process_log)
        self._timer = QTimer(self)
        self._timer.setInterval(10_000)
        self._timer.timeout.connect(self._refresh_status_background)
        self._timer.start()
        QTimer.singleShot(250, self._refresh_status_background)
        QTimer.singleShot(400, self.refreshLogs)

    @Property("QVariantMap", notify=configChanged)
    def configData(self) -> dict[str, object]:
        return {
            "host": self.config.host,
            "port": str(self.config.port),
            "comfyUrl": self.config.comfy_url,
            "dataDir": self.config.data_dir,
            "workflowDir": self.config.workflow_dir,
            "comfyLogPath": self.config.comfy_log_path,
            "debug": self.config.debug,
            "frpEnabled": self.config.frp_enabled,
            "frpExecutable": self.config.frp_executable,
            "frpConfigPath": self.config.frp_config_path,
            "frpServerAddr": self.config.frp_server_addr,
            "frpServerPort": str(self.config.frp_server_port),
            "frpAuthToken": self.config.frp_auth_token,
            "frpRemotePort": str(self.config.frp_remote_port),
            "frpTls": self.config.frp_tls,
            "frpEncryption": self.config.frp_encryption,
            "frpCompression": self.config.frp_compression,
            "publicAgentUrl": self.config.public_agent_url,
            "localAgentUrl": self.config.local_agent_url,
            "resolvedPublicUrl": self.config.resolved_public_url or "尚未配置",
            "frpMapping": f"公网 {self.config.frp_remote_port} → 本机 {self.config.port}",
        }

    @Property("QVariantMap", notify=statusChanged)
    def statusData(self) -> dict[str, dict[str, object]]:
        return self._status

    @Property(bool, notify=checkingChanged)
    def checking(self) -> bool:
        return self._checking

    @Property(str, notify=summaryChanged)
    def summary(self) -> str:
        return self._summary

    @Property(str, notify=tokenChanged)
    def deviceToken(self) -> str:
        return self._token

    @Property("QVariantMap", notify=logsChanged)
    def logData(self) -> dict[str, str]:
        return self._logs

    @Slot("QVariantMap", result=bool)
    def saveConfig(self, raw: dict[str, Any]) -> bool:
        try:
            updated = _config_from_map(raw)
            updated.save()
        except (OSError, ValueError) as error:
            self.toastRequested.emit("配置保存失败", str(error))
            return False
        old_token_path = self.config.token_path
        self.config = updated
        if old_token_path != updated.token_path:
            self._token = updated.load_or_create_device_token()
            self.tokenChanged.emit()
        self.configChanged.emit()
        self.toastRequested.emit("配置已保存", "Bridge 与 FRP 配置已经更新。")
        return True

    @Slot("QVariantMap")
    def startAll(self, raw: dict[str, Any]) -> None:
        if self.saveConfig(raw):
            self._run_service_action("全部服务已启动", lambda: self.manager.start_all(self.config))

    @Slot("QVariantMap")
    def startAgent(self, raw: dict[str, Any]) -> None:
        if self.saveConfig(raw):
            self._run_service_action("Bridge 已启动", lambda: self.manager.start_agent(self.config))

    @Slot("QVariantMap")
    def startFrp(self, raw: dict[str, Any]) -> None:
        if self.saveConfig(raw):
            self._run_service_action("FRP 已启动", lambda: self.manager.start_frp(self.config))

    @Slot()
    def stopAll(self) -> None:
        self._run_service_action("服务已停止", self.manager.stop_all)

    @Slot()
    def refreshStatus(self) -> None:
        self._begin_status_refresh(manual=True)

    @Slot()
    def _refresh_status_background(self) -> None:
        self._begin_status_refresh(manual=False)

    def _begin_status_refresh(self, *, manual: bool) -> None:
        if self._refreshing:
            return
        self._refreshing = True
        if manual:
            self._checking = True
            self._summary = "正在检测全部服务…"
            self._status = {
                key: {"label": "检查中", "online": False, "tone": "checking"}
                for key in ("agent", "comfy", "frp", "public")
            }
            self.checkingChanged.emit()
            self.summaryChanged.emit()
            self.statusChanged.emit()

        def worker() -> None:
            try:
                agent_ok, agent_detail = _check_endpoint(self.config.local_agent_url + "/health")
                comfy_ok, comfy_detail = _check_endpoint(
                    self.config.comfy_url.rstrip("/") + "/system_stats"
                )
                public_url = self.config.resolved_public_url
                if public_url:
                    public_ok, public_detail = _check_endpoint(public_url + "/health")
                else:
                    public_ok, public_detail = False, "未配置"
                frp_ok = self.manager.frp_running or public_ok
                result = {
                    "agent": _status_item(agent_ok, "在线", agent_detail),
                    "comfy": _status_item(comfy_ok, "在线", comfy_detail),
                    "frp": _status_item(frp_ok, "已连接", "未运行"),
                    "public": _status_item(public_ok, "可访问", public_detail),
                }
            except Exception as error:
                result = {
                    key: _status_item(False, "在线", f"检测失败：{error}")
                    for key in ("agent", "comfy", "frp", "public")
                }
            self._statusReady.emit(result)

        threading.Thread(target=worker, daemon=True, name="qt-status-check").start()

    @Slot()
    def refreshLogs(self) -> None:
        config = self.config

        def worker() -> None:
            self._logsReady.emit(
                {
                    "bridge": _read_tail(config.agent_log_path),
                    "frp": _read_tail(config.frp_log_path),
                    "comfy": _read_comfy_log(config),
                }
            )

        threading.Thread(target=worker, daemon=True, name="qt-log-refresh").start()

    @Slot(result=str)
    def copyDeviceToken(self) -> str:
        QApplication.clipboard().setText(self._token)
        self.toastRequested.emit("已复制", "设备密钥已复制到剪贴板。")
        return self._token

    @Slot()
    def regenerateDeviceToken(self) -> None:
        if self.manager.agent_running:
            self.toastRequested.emit("请先停止 Bridge", "停止服务后才能重新生成设备密钥。")
            return
        answer = QMessageBox.question(
            None,
            "重新生成设备密钥",
            "手机中保存的旧密钥将失效，确定继续吗？",
        )
        if answer != QMessageBox.StandardButton.Yes:
            return
        try:
            self._token = self.config.regenerate_device_token()
        except OSError as error:
            self.toastRequested.emit("生成失败", str(error))
            return
        self.tokenChanged.emit()
        self.toastRequested.emit("密钥已更新", "请在手机设置中填写新密钥。")

    @Slot(str, result=str)
    def browseDirectory(self, current: str) -> str:
        return QFileDialog.getExistingDirectory(None, "选择目录", current or str(Path.home()))

    @Slot(str, result=str)
    def browseFile(self, current: str) -> str:
        start = str(Path(current).parent) if current else str(Path.home())
        path, _selected_filter = QFileDialog.getOpenFileName(None, "选择文件", start)
        return path

    @Slot()
    def openAgentLogDirectory(self) -> None:
        self.config.agent_log_path.parent.mkdir(parents=True, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.config.agent_log_path.parent)))

    @Slot()
    def openFrpLogDirectory(self) -> None:
        self.config.frp_log_path.parent.mkdir(parents=True, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.config.frp_log_path.parent)))

    @Slot()
    def reloadConfig(self) -> None:
        self.config = DesktopConfig.load()
        self._token = self.config.load_or_create_device_token()
        self.configChanged.emit()
        self.tokenChanged.emit()
        self.toastRequested.emit("配置已恢复", "已经重新读取磁盘中的配置。")

    def shutdown(self) -> None:
        self._timer.stop()
        self.manager.stop_all()

    def _run_service_action(self, success: str, action: Callable[[], None]) -> None:
        def worker() -> None:
            try:
                action()
            except Exception as error:
                self._serviceFinished.emit("服务操作失败", str(error))
            else:
                self._serviceFinished.emit(success, "")

        threading.Thread(target=worker, daemon=True, name="qt-service-action").start()

    def _receive_process_log(self, channel: str, line: str) -> None:
        self._processLog.emit(channel, line)

    @Slot(object)
    def _apply_status(self, payload: object) -> None:
        if not isinstance(payload, dict):
            self._refreshing = False
            if self._checking:
                self._checking = False
                self.checkingChanged.emit()
            return
        self._status = payload
        self._refreshing = False
        online_count = sum(bool(item.get("online")) for item in self._status.values())
        self._summary = f"{online_count}/4 项连接正常"
        self.statusChanged.emit()
        if self._checking:
            self._checking = False
            self.checkingChanged.emit()
        self.summaryChanged.emit()

    @Slot(object)
    def _apply_logs(self, payload: object) -> None:
        if isinstance(payload, dict):
            self._logs = {str(key): str(value) for key, value in payload.items()}
            self.logsChanged.emit()

    @Slot(str, str)
    def _handle_service_finished(self, title: str, detail: str) -> None:
        self.toastRequested.emit(title, detail or "操作已完成。")
        QTimer.singleShot(350, self._refresh_status_background)
        QTimer.singleShot(500, self.refreshLogs)

    @Slot(str, str)
    def _append_process_log(self, channel: str, line: str) -> None:
        current = self._logs.get(channel, "")
        lines = (current + "\n" + line).splitlines()[-500:]
        self._logs[channel] = "\n".join(lines)
        self.logsChanged.emit()


def _config_from_map(raw: dict[str, Any]) -> DesktopConfig:
    try:
        port = int(str(raw.get("port", "")))
        frp_server_port = int(str(raw.get("frpServerPort", "")))
        frp_remote_port = int(str(raw.get("frpRemotePort", "")))
    except ValueError as error:
        raise ValueError("端口必须填写数字。") from error
    return DesktopConfig(
        host=str(raw.get("host", "")).strip(),
        port=port,
        comfy_url=str(raw.get("comfyUrl", "")).strip(),
        data_dir=str(raw.get("dataDir", "")).strip(),
        workflow_dir=str(raw.get("workflowDir", "")).strip(),
        comfy_log_path=str(raw.get("comfyLogPath", "")).strip(),
        debug=bool(raw.get("debug", False)),
        frp_enabled=bool(raw.get("frpEnabled", False)),
        frp_executable=str(raw.get("frpExecutable", "")).strip(),
        frp_config_path=str(raw.get("frpConfigPath", "")).strip(),
        frp_server_addr=str(raw.get("frpServerAddr", "")).strip(),
        frp_server_port=frp_server_port,
        frp_auth_token=str(raw.get("frpAuthToken", "")).strip(),
        frp_remote_port=frp_remote_port,
        frp_tls=bool(raw.get("frpTls", True)),
        frp_encryption=bool(raw.get("frpEncryption", True)),
        frp_compression=bool(raw.get("frpCompression", False)),
        public_agent_url=str(raw.get("publicAgentUrl", "")).strip(),
    )


def _check_endpoint(url: str) -> tuple[bool, str]:
    try:
        with urlopen(Request(url, headers={"Accept": "application/json"}), timeout=3) as response:
            status = int(response.status)
            return (True, "在线") if 200 <= status < 300 else (False, f"HTTP {status}")
    except HTTPError as error:
        return False, f"HTTP {error.code}"
    except (URLError, TimeoutError, OSError):
        return False, "离线"


def _status_item(online: bool, success: str, failure: str) -> dict[str, object]:
    return {
        "label": success if online else failure,
        "online": online,
        "tone": "online" if online else ("muted" if failure == "未配置" else "offline"),
    }


def _read_tail(path: Path, limit: int = 500) -> str:
    if not path.is_file():
        return f"日志文件尚不存在：\n{path}"
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as error:
        return f"无法读取日志：{error}"
    return "\n".join(lines[-limit:])


def _read_comfy_log(config: DesktopConfig) -> str:
    if config.comfy_log_path.strip():
        return _read_tail(Path(config.comfy_log_path))
    url = config.comfy_url.rstrip("/") + "/internal/logs/raw"
    try:
        request = Request(url, headers={"Accept": "application/json, text/plain"})
        with urlopen(request, timeout=4) as response:
            content = bytes(response.read()).decode("utf-8", errors="replace")
        try:
            decoded = json.loads(content)
        except json.JSONDecodeError:
            return content
        return (
            decoded
            if isinstance(decoded, str)
            else json.dumps(decoded, ensure_ascii=False, indent=2)
        )
    except (HTTPError, URLError, TimeoutError, OSError) as error:
        return (
            "未能从 ComfyUI 日志接口读取日志。\n"
            "可在“服务配置”页指定 ComfyUI 日志文件。\n\n"
            f"详细信息：{error}"
        )
