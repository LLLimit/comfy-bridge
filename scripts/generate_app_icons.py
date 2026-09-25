from __future__ import annotations

import struct
from pathlib import Path

from PySide6.QtCore import QByteArray, QBuffer, QIODevice, QRectF, Qt
from PySide6.QtGui import QColor, QImage, QLinearGradient, QPainter, QPainterPath


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "assets" / "branding" / "comfy-bridge-master.png"
DESKTOP_ASSETS = ROOT / "apps" / "agent" / "src" / "comfy_bridge" / "desktop" / "assets"
ANDROID_RES = ROOT / "apps" / "mobile" / "android" / "app" / "src" / "main" / "res"


def draw_icon(size: int, *, background: bool, foreground_scale: float = 0.76) -> QImage:
    source = QImage(str(MASTER))
    if source.isNull():
        raise RuntimeError(f"Unable to load icon master: {MASTER}")

    canvas = QImage(size, size, QImage.Format.Format_ARGB32_Premultiplied)
    canvas.fill(Qt.GlobalColor.transparent)
    painter = QPainter(canvas)
    painter.setRenderHints(
        QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform
    )

    if background:
        inset = max(1.0, size * 0.025)
        box = QRectF(inset, inset, size - inset * 2, size - inset * 2)
        path = QPainterPath()
        path.addRoundedRect(box, size * 0.225, size * 0.225)
        gradient = QLinearGradient(0, 0, size, size)
        gradient.setColorAt(0.0, QColor("#181C33"))
        gradient.setColorAt(0.55, QColor("#101528"))
        gradient.setColorAt(1.0, QColor("#080C18"))
        painter.fillPath(path, gradient)

    target_size = size * foreground_scale
    target = QRectF(
        (size - target_size) / 2,
        (size - target_size) / 2,
        target_size,
        target_size,
    )
    painter.drawImage(target, source)
    painter.end()
    return canvas


def image_png_bytes(image: QImage) -> bytes:
    data = QByteArray()
    buffer = QBuffer(data)
    buffer.open(QIODevice.OpenModeFlag.WriteOnly)
    if not image.save(buffer, "PNG"):
        raise RuntimeError("Unable to encode PNG")
    return bytes(data)


def write_ico(path: Path, sizes: tuple[int, ...]) -> None:
    payloads = [image_png_bytes(draw_icon(size, background=True)) for size in sizes]
    header_size = 6 + 16 * len(sizes)
    offset = header_size
    entries: list[bytes] = []
    for size, payload in zip(sizes, payloads, strict=True):
        dimension = 0 if size == 256 else size
        entries.append(
            struct.pack(
                "<BBBBHHII",
                dimension,
                dimension,
                0,
                0,
                1,
                32,
                len(payload),
                offset,
            )
        )
        offset += len(payload)
    path.write_bytes(struct.pack("<HHH", 0, 1, len(sizes)) + b"".join(entries) + b"".join(payloads))


def main() -> None:
    DESKTOP_ASSETS.mkdir(parents=True, exist_ok=True)
    desktop_png = DESKTOP_ASSETS / "comfy-bridge.png"
    draw_icon(512, background=True).save(str(desktop_png), "PNG")
    write_ico(
        DESKTOP_ASSETS / "comfy-bridge.ico",
        (16, 24, 32, 48, 64, 128, 256),
    )

    densities = {
        "mdpi": (48, 108),
        "hdpi": (72, 162),
        "xhdpi": (96, 216),
        "xxhdpi": (144, 324),
        "xxxhdpi": (192, 432),
    }
    for density, (legacy_size, adaptive_size) in densities.items():
        destination = ANDROID_RES / f"mipmap-{density}"
        destination.mkdir(parents=True, exist_ok=True)
        draw_icon(legacy_size, background=True).save(
            str(destination / "ic_launcher.png"), "PNG"
        )
        draw_icon(adaptive_size, background=False, foreground_scale=0.68).save(
            str(destination / "ic_launcher_foreground.png"), "PNG"
        )

    print(f"Generated desktop and Android icons from {MASTER}")


if __name__ == "__main__":
    main()
