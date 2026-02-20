from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator

Domain = Literal[
    "calendar",
    "reminders",
    "mail",
    "notes",
    "files",
    "photos",
    "contacts",
    "location",
    "memory",
]

Operation = Literal[
    "count",
    "list",
    "sum_duration",
    "group_by_day",
    "group_by_type",
    "latest",
    "exists",
]
Mode = Literal["info"]
TimeScopeType = Literal["relative", "absolute", "all"]
TimeScopeValue = Literal["today", "7d", "30d", "3m", "1y"]
Grouping = Literal["day", "week", "month", "type", "location", "status", "none"]
SortOption = Literal["date_desc", "date_asc", "duration", "name", "priority", "none"]


class TimeScopeDTO(BaseModel):
    type: TimeScopeType
    value: Optional[TimeScopeValue] = None
    start: Optional[datetime] = Field(default=None, description="UTC ISO8601 datetime")
    end: Optional[datetime] = Field(default=None, description="UTC ISO8601 datetime")


class IntentPlanDTO(BaseModel):
    model_config = ConfigDict(extra="forbid")

    domain: Domain
    mode: Mode = "info"
    operation: Operation = "count"
    time_scope: TimeScopeDTO
    filters: Dict[str, Any] = Field(default_factory=dict)
    grouping: Optional[Grouping] = "none"
    sort: Optional[SortOption] = "none"
    needs_clarification: bool = False
    clarification_message: Optional[str] = None
    suggestions: List[Domain] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_clarification_state(self) -> "IntentPlanDTO":
        if self.time_scope.type == "relative" and self.time_scope.value is None:
            raise ValueError("time_scope.value is required when time_scope.type is 'relative'")
        if self.time_scope.type != "relative" and self.time_scope.value is not None:
            raise ValueError("time_scope.value must be null unless time_scope.type is 'relative'")
        if self.needs_clarification and not self.clarification_message:
            raise ValueError("clarification_message is required when needs_clarification is true")
        if not self.needs_clarification and self.clarification_message is not None:
            raise ValueError("clarification_message must be null when needs_clarification is false")
        return self
