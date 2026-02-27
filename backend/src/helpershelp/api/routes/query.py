from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field, model_validator

from helpershelp.api.models import DataIntent
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
    try:
        user_query = request.resolved_query
        if not user_query:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty query")

        tz = request.timezone or "Europe/Stockholm"
        logger.info(
            "Processing query route lang=%s tz=%s chars=%d",
            request.language,
            tz,
            len(user_query),
        )

        router_service = DataIntentRouter(timezone_name=tz)
        plan = router_service.route(user_query, language=request.language)

        # Convert router result (dict) into a DataIntent model instance
        data_intent = DataIntent.model_validate(plan)
        return QueryResponse(data_intent=data_intent)

    except HTTPException:
        raise
    except Exception as exc:
        logger.error(
            "Query processing failed route=/query lang=%s tz=%s exc_type=%s",
            request.language,
            request.timezone or "Europe/Stockholm",
            exc.__class__.__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal error",
        ) from exc
