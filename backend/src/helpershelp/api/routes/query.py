from __future__ import annotations

import logging
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, model_validator

from helpershelp.api.deps import get_assistant_store, get_query_orchestrator
from helpershelp.api.models import LLMResponse
from helpershelp.infrastructure.llm.bge_m3_adapter import EmbeddingBackendUnavailableError

logger = logging.getLogger(__name__)

router = APIRouter()


class QueryRequest(BaseModel):
    query: Optional[str] = None
    question: Optional[str] = None
    language: str = "sv"
    sources: Optional[List[str]] = None
    days: int = 90
    data_filter: Optional[dict] = None

    @model_validator(mode="after")
    def validate_input(self):
        if not self.query and not self.question:
            raise ValueError("Either 'query' or 'question' must be provided")
        return self

    @property
    def resolved_query(self) -> str:
        return self.query or self.question or ""


@router.post("/query", response_model=LLMResponse, tags=["query"])
async def unified_query(request: QueryRequest):
    try:
        user_query = request.resolved_query
        logger.info("Processing query: %s", user_query)

        payload = await get_query_orchestrator().handle(
            user_query=user_query,
            language=request.language,
            sources=request.sources,
            days=request.days,
            data_filter=request.data_filter,
        )
        return LLMResponse(**payload)
    except HTTPException:
        raise
    except EmbeddingBackendUnavailableError as exc:
        logger.error("Query processing failed (embedding backend unavailable): %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        logger.error("Query processing failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal error: {str(exc)}",
        ) from exc
