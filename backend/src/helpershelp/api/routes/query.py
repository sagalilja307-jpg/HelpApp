from __future__ import annotations

import logging
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, model_validator

from helpershelp.api.deps import get_data_intent_router
from helpershelp.api.models import QueryDataIntentResponse

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


@router.post("/query", response_model=QueryDataIntentResponse, tags=["query"])
async def unified_query(request: QueryRequest):
    try:
        user_query = request.resolved_query
        logger.info("Processing query: %s", user_query)
        payload = get_data_intent_router().route(
            query=user_query,
            language=request.language,
        )
        return QueryDataIntentResponse(data_intent=payload)
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Query processing failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal error: {str(exc)}",
        ) from exc
