from __future__ import annotations

from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field

from helpershelp.application.intent.intent_plan import Domain, Grouping, Operation, SortOption, TimeScopeDTO

DataIntentDomain = Domain | Literal["system"]
DataIntentOperation = Operation | Literal["needs_clarification"]


class DataIntent(BaseModel):
    domain: DataIntentDomain
    mode: Literal["info"] = "info"
    operation: DataIntentOperation
    time_scope: TimeScopeDTO
    filters: Dict[str, Any] = Field(default_factory=dict)
    grouping: Optional[Grouping] = "none"
    sort: Optional[SortOption] = "none"
    needs_clarification: bool = False
    clarification_message: Optional[str] = None
    suggestions: List[Domain] = Field(default_factory=list)


class QueryDataIntentResponse(BaseModel):
    data_intent: DataIntent


class UnifiedQueryRequest(BaseModel):
    query: str
    language: str = "sv"
    sources: Optional[List[str]] = None
    days: int = 90
    data_filter: Optional[dict] = None
