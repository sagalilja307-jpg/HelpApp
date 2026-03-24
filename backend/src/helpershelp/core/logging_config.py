from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from logging.config import dictConfig
from typing import Any

from helpershelp.core.config import get_log_format, get_log_level

_RESERVED_LOG_RECORD_FIELDS = frozenset(logging.makeLogRecord({}).__dict__.keys()) | {
    "message",
    "asctime",
}


def build_log_extra(**fields: Any) -> dict[str, Any]:
    return {
        key: value
        for key, value in fields.items()
        if value is not None
    }


class JsonLogFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)

        for key, value in record.__dict__.items():
            if key in _RESERVED_LOG_RECORD_FIELDS or key.startswith("_"):
                continue
            payload[key] = self._normalize(value)

        return json.dumps(payload, ensure_ascii=False)

    @staticmethod
    def _normalize(value: Any) -> Any:
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        if isinstance(value, PathLikeJSONTypes):
            return [JsonLogFormatter._normalize(item) for item in value]
        if isinstance(value, dict):
            return {
                str(key): JsonLogFormatter._normalize(item)
                for key, item in value.items()
            }
        return str(value)


class TextLogFormatter(logging.Formatter):
    def __init__(self) -> None:
        super().__init__(
            fmt="%(asctime)s %(levelname)s %(name)s %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S%z",
        )


PathLikeJSONTypes = (list, tuple, set, frozenset)


def build_logging_config() -> dict[str, Any]:
    formatter_name = "text" if get_log_format() == "text" else "json"
    log_level = get_log_level()

    return {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "json": {"()": "helpershelp.core.logging_config.JsonLogFormatter"},
            "text": {"()": "helpershelp.core.logging_config.TextLogFormatter"},
        },
        "handlers": {
            "default": {
                "class": "logging.StreamHandler",
                "formatter": formatter_name,
                "level": log_level,
            }
        },
        "root": {
            "handlers": ["default"],
            "level": log_level,
        },
    }


def configure_logging() -> None:
    dictConfig(build_logging_config())
