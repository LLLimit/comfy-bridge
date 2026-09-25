from __future__ import annotations

import logging
import re
from logging.handlers import RotatingFileHandler

import uvicorn

from comfy_bridge.api.app import create_app
from comfy_bridge.core.settings import Settings


class _RedactTokenFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        redacted = re.sub(r"([?&]token=)[^&\s\"]+", r"\1<redacted>", message)
        if redacted != message:
            record.msg = redacted
            record.args = ()
        return True


def main() -> None:
    settings = Settings.load()
    settings.ensure_directories()
    log_file = settings.data_dir / "agent.log"
    redactor = _RedactTokenFilter()
    stream_handler = logging.StreamHandler()
    file_handler = RotatingFileHandler(
        log_file,
        maxBytes=2 * 1024 * 1024,
        backupCount=2,
        encoding="utf-8",
    )
    stream_handler.addFilter(redactor)
    file_handler.addFilter(redactor)
    logging.basicConfig(
        level=logging.DEBUG if settings.debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        handlers=[stream_handler, file_handler],
        force=True,
    )
    uvicorn.run(
        create_app(settings),
        host=settings.host,
        port=settings.port,
        log_config=None,
        access_log=False,
    )


if __name__ == "__main__":
    main()
