from __future__ import annotations

import os
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[3]
DEFAULT_LOG_FORMAT = "json"
DEFAULT_LOG_LEVEL = "INFO"


def get_default_db_path() -> Path:
    return (BACKEND_DIR / "data" / "helpershelp.db").expanduser()


def get_runtime_environment() -> str:
    return (os.getenv("HELPERSHELP_ENV", "") or "").strip().lower()


def get_cors_allow_origins() -> list[str]:
    raw_origins = os.getenv("HELPERSHELP_CORS_ALLOW_ORIGINS")
    if raw_origins is not None:
        return [origin.strip() for origin in raw_origins.split(",") if origin.strip()]

    environment = get_runtime_environment()
    if environment in {"", "dev", "development"}:
        return ["*"]
    return []


def get_log_format() -> str:
    requested = (os.getenv("HELPERSHELP_LOG_FORMAT", DEFAULT_LOG_FORMAT) or "").strip().lower()
    return "text" if requested == "text" else "json"


def get_log_level() -> str:
    requested = (os.getenv("HELPERSHELP_LOG_LEVEL", DEFAULT_LOG_LEVEL) or "").strip().upper()
    return requested or DEFAULT_LOG_LEVEL


DEFAULT_DB_PATH = get_default_db_path()
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:7b")
OLLAMA_EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL", "bge-m3")
