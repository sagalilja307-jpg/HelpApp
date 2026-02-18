from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field


class DataIntentTimeframe(BaseModel):
    start: datetime
    end: datetime
    granularity: Literal["day", "week", "month", "custom"]


class DataIntentSort(BaseModel):
    field: str
    direction: Literal["asc", "desc"]


class DataIntent(BaseModel):
    domain: Literal[
        "calendar",
        "reminders",
        "mail",
        "contacts",
        "photos",
        "files",
        "location",
        "notes",
        "system",
    ]
    operation: Literal["list", "count", "next", "details", "search", "needs_clarification"]
    timeframe: Optional[DataIntentTimeframe] = None
    filters: Optional[Dict[str, Any]] = None
    sort: Optional[DataIntentSort] = None
    limit: Optional[int] = Field(default=None, ge=1)
    fields: Optional[List[str]] = None


class QueryDataIntentResponse(BaseModel):
    data_intent: DataIntent


class UnifiedQueryRequest(BaseModel):
    query: str
    language: str = "sv"
    sources: Optional[List[str]] = None
    days: int = 90
    data_filter: Optional[dict] = None
