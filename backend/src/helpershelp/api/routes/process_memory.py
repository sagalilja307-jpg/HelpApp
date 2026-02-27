from __future__ import annotations

import logging
import re
from collections import Counter
from typing import List

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field, field_validator

from helpershelp.core.config import OLLAMA_EMBED_MODEL
from helpershelp.llm import get_embedding_service

logger = logging.getLogger(__name__)
router = APIRouter()

MAX_TEXT_LENGTH = 8_000
REQUIRED_EMBED_PREFIX = "bge-m3"

_STOP_WORDS = {
    "och",
    "att",
    "det",
    "som",
    "den",
    "detta",
    "jag",
    "du",
    "vi",
    "ni",
    "är",
    "var",
    "för",
    "med",
    "till",
    "på",
    "av",
    "om",
    "in",
    "the",
    "a",
    "an",
    "to",
    "of",
    "for",
    "and",
    "is",
}


class ProcessMemoryRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=MAX_TEXT_LENGTH)
    language: str = Field(default="sv", min_length=2, max_length=8)

    @field_validator("text")
    @classmethod
    def validate_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("text must not be empty")
        return value

    @field_validator("language")
    @classmethod
    def validate_language(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not normalized:
            raise ValueError("language must not be empty")
        return normalized


class ProcessMemoryResponse(BaseModel):
    cleanText: str
    suggestedType: str
    tags: List[str]
    embedding: List[float]


def _model_prefix(value: str) -> str:
    return (value or "").strip().lower().split(":")[0]


def _is_allowed_model(value: str) -> bool:
    return _model_prefix(value) == REQUIRED_EMBED_PREFIX


def _clean_text(raw: str) -> str:
    single_spaced = re.sub(r"\s+", " ", raw).strip()
    # Trim common bullet prefixes but keep semantic content.
    return re.sub(r"^[\-\*\u2022]\s*", "", single_spaced)


def _suggested_type(clean_text: str) -> str:
    lower = clean_text.lower()
    if any(token in lower for token in ("beslut", "decide", "decision")):
        return "Decision"
    if any(token in lower for token in ("idé", "idea", "förslag", "proposal")):
        return "Idea"
    if any(token in lower for token in ("problem", "risk", "issue", "blocker")):
        return "Risk"
    if "?" in clean_text:
        return "Question"
    return "Insight"


def _tags(clean_text: str) -> List[str]:
    tokens = re.findall(r"[a-zA-Z0-9åäöÅÄÖ]{3,}", clean_text.lower())
    filtered = [token for token in tokens if token not in _STOP_WORDS]
    if not filtered:
        return ["memory"]
    counts = Counter(filtered)
    ranked = sorted(counts.items(), key=lambda item: (-item[1], -len(item[0]), item[0]))
    return [token for token, _ in ranked[:5]]


@router.post("/process-memory", response_model=ProcessMemoryResponse, tags=["memory"])
async def process_memory(request: ProcessMemoryRequest) -> ProcessMemoryResponse:
    route = "/process-memory"
    timezone_name = "n/a"

    configured_model = (OLLAMA_EMBED_MODEL or "").strip()
    if not _is_allowed_model(configured_model):
        logger.error(
            "Memory request route=%s lang=%s tz=%s status=%d reason=config_model",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )

    embed_service = get_embedding_service()
    try:
        runtime = embed_service.status()
    except Exception as exc:
        logger.warning(
            "Memory request route=%s lang=%s tz=%s status=%d reason=runtime_status exc_type=%s",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
            exc.__class__.__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        ) from exc
    if not _is_allowed_model(runtime.embedding_model):
        logger.error(
            "Memory request route=%s lang=%s tz=%s status=%d reason=runtime_model",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )
    if not runtime.model_available:
        logger.warning(
            "Memory request route=%s lang=%s tz=%s status=%d reason=model_unavailable",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )

    clean_text = _clean_text(request.text)
    suggested_type = _suggested_type(clean_text)
    tags = _tags(clean_text)

    try:
        vectors = embed_service.embed_texts([clean_text])
    except Exception as exc:
        logger.warning(
            "Memory request route=%s lang=%s tz=%s status=%d reason=embed_backend exc_type=%s",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
            exc.__class__.__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        ) from exc

    if not vectors or not vectors[0]:
        logger.error(
            "Memory request route=%s lang=%s tz=%s status=%d reason=empty_vector",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )

    logger.info(
        "Memory request route=%s lang=%s tz=%s status=%d",
        route,
        request.language,
        timezone_name,
        status.HTTP_200_OK,
    )

    return ProcessMemoryResponse(
        cleanText=clean_text,
        suggestedType=suggested_type,
        tags=tags,
        embedding=[float(value) for value in vectors[0]],
    )
