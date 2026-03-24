from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field, model_validator

from helpershelp.api.models import DataIntent
from helpershelp.core.logging_config import build_log_extra
from helpershelp.query.data_intent_router import DataIntentRouter

logger = logging.getLogger(__name__)
router = APIRouter()


# --- Request/Response DTOs (API layer) ---

class QueryRequest(BaseModel):
    # iOS skickar bara "query", men vi behåller "question" som bakåtkomp.
    query: Optional[str] = None
    question: Optional[str] = None

    language: str = "sv"

    # Hint för lokal tolkning (backend gör all matte).
    timezone: Optional[str] = Field(default=None, description="IANA TZ, ex: Europe/Stockholm")

    @model_validator(mode="after")
    def validate_input(self):
        if not self.query and not self.question:
            raise ValueError("Either 'query' or 'question' must be provided")
        return self

    @property
    def resolved_query(self) -> str:
        return (self.query or self.question or "").strip()


class QueryResponse(BaseModel):
    data_intent: DataIntent


# --- Endpoint ---

@router.post("/query", response_model=QueryResponse, tags=["query"])
async def unified_query(request: QueryRequest) -> QueryResponse:
    tz = request.timezone or "Europe/Stockholm"
    try:
        user_query = request.resolved_query
        if not user_query:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty query")

        router_service = DataIntentRouter(timezone_name=tz)
        plan = router_service.route(user_query, language=request.language)

        # Convert router result (dict) into a DataIntent model instance
        data_intent = DataIntent.model_validate(plan)
        logger.info(
            "Query request route=/query lang=%s tz=%s status=%d",
            request.language,
            tz,
            status.HTTP_200_OK,
            extra=build_log_extra(
                route="/query",
                lang=request.language,
                tz=tz,
                status=status.HTTP_200_OK,
            ),
        )
        return QueryResponse(data_intent=data_intent)

    except HTTPException as exc:
        logger.warning(
            "Query request route=/query lang=%s tz=%s status=%d",
            request.language,
            tz,
            exc.status_code,
            extra=build_log_extra(
                route="/query",
                lang=request.language,
                tz=tz,
                status=exc.status_code,
            ),
        )
        raise
    except Exception as exc:
        logger.error(
            "Query request route=/query lang=%s tz=%s status=%d exc_type=%s",
            request.language,
            tz,
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            exc.__class__.__name__,
            extra=build_log_extra(
                route="/query",
                lang=request.language,
                tz=tz,
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
                exc_type=exc.__class__.__name__,
            ),
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal error",
        ) from exc
