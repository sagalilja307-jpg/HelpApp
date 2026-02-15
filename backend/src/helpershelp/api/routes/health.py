from __future__ import annotations

import os

from fastapi import APIRouter

from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.config import DEFAULT_DB_PATH

router = APIRouter()


@router.get("/health", tags=["system"])
def health_check():
    return {"status": "ok"}


@router.get("/healthz", tags=["system"])
def health_check_extended():
    return {"status": "ok", "timestamp": utcnow().isoformat()}


@router.get("/health/details", tags=["system"])
def health_details():
    db_path = os.getenv("HELPERSHELP_DB_PATH", str(DEFAULT_DB_PATH))
    return {
        "status": "ok",
        "timestamp": utcnow().isoformat(),
        "db_path": db_path,
        "sync_loop_enabled": os.getenv("HELPERSHELP_ENABLE_SYNC_LOOP", "0") == "1",
        "model": {
            "embedding": "bge-m3",
            "generation": "qwen2.5:7b (Ollama)",
        },
    }
