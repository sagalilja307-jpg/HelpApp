from __future__ import annotations

import logging
import os

from fastapi import APIRouter, HTTPException, status

from helpershelp.core.time_utils import utcnow
from helpershelp.core.config import DEFAULT_DB_PATH, OLLAMA_EMBED_MODEL
from helpershelp.llm import get_embedding_service

router = APIRouter()
logger = logging.getLogger(__name__)

REQUIRED_EMBED_PREFIX = "bge-m3"


def _model_prefix(value: str) -> str:
    return (value or "").strip().lower().split(":")[0]


def _is_allowed_model(value: str) -> bool:
    return _model_prefix(value) == REQUIRED_EMBED_PREFIX


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
    }


@router.get("/health/ready", tags=["system"])
def readiness_check():
    configured_model = (OLLAMA_EMBED_MODEL or "").strip()
    if not _is_allowed_model(configured_model):
        logger.error("Readiness check failed route=/health/ready reason=config_model")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Service unavailable",
        )

    embed_service = get_embedding_service()
    try:
        runtime = embed_service.status()
    except Exception as exc:
        logger.warning(
            "Readiness check failed route=/health/ready reason=runtime_status exc_type=%s",
            exc.__class__.__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Service unavailable",
        ) from exc

    if not _is_allowed_model(runtime.embedding_model):
        logger.error("Readiness check failed route=/health/ready reason=runtime_model")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Service unavailable",
        )

    if not runtime.model_available:
        logger.warning("Readiness check failed route=/health/ready reason=model_unavailable")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Service unavailable",
        )

    return {
        "status": "ready",
        "timestamp": utcnow().isoformat(),
        "embeddingModel": runtime.embedding_model,
        "activeEmbedEndpoint": runtime.active_embed_endpoint,
    }
