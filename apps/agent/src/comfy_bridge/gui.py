from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Comfy Bridge Windows control center")
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate saved desktop and FRP configuration without opening the GUI",
    )
    args = parser.parse_args()
    if args.check:
        from comfy_bridge.desktop.config import DesktopConfig

        config = DesktopConfig.load()
        config.validate()
        print("Comfy Bridge desktop configuration is valid.")
        return

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuickControls2 import QQuickStyle
    from PySide6.QtWidgets import QApplication

    from comfy_bridge.desktop.qt_backend import DesktopBackend

    os.environ.setdefault("QT_QUICK_CONTROLS_FLUENTWINUI3_THEME", "Dark")
    if sys.platform == "win32":
        import ctypes

        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
            "ComfyBridge.ControlCenter"
        )
    QGuiApplication.setApplicationName("Comfy Bridge")
    QGuiApplication.setOrganizationName("Comfy Bridge")
    QQuickStyle.setStyle("FluentWinUI3")
    app = QApplication(sys.argv[:1])
    icon_path = Path(__file__).resolve().parent / "desktop" / "assets" / "comfy-bridge.ico"
    app.setWindowIcon(QIcon(str(icon_path)))
    backend = DesktopBackend()
    app.aboutToQuit.connect(backend.shutdown)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    qml_path = Path(__file__).resolve().parent / "desktop" / "qml" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_path)))
    if not engine.rootObjects():
        raise RuntimeError(f"Unable to load desktop UI: {qml_path}")
    exit_code = app.exec()
    engine.deleteLater()
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
