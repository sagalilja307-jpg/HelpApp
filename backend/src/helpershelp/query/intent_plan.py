from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Literal, Optional

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
    "health",
]
IntentPlanDomain = Domain | Literal["system"]

Operation = Literal[
    "count",
    "list",
    "exists",
    "sum",
    "sum_duration",
    "latest",
]
IntentPlanOperation = Operation | Literal["needs_clarification"]
Mode = Literal["info"]
TimeScopeType = Literal["relative", "absolute", "all"]
TimeScopeValue = Literal[
    "today",
    "today_morning",
    "today_day",
    "today_afternoon",
    "today_evening",
    "tomorrow_morning",
    "7d",
    "30d",
    "3m",
    "1y",
]


class TimeScopeDTO(BaseModel):
    type: TimeScopeType
    value: Optional[str] = None
    start: Optional[datetime] = None
    end: Optional[datetime] = None

    @model_validator(mode="after")
    def validate_value_required(self) -> "TimeScopeDTO":
        has_bounds = self.start is not None and self.end is not None
        has_partial_bounds = (self.start is None) != (self.end is None)

        if has_partial_bounds:
            raise ValueError("time scope requires both start and end when one bound is set")

        if self.type != "all" and self.value is None and not has_bounds:
            raise ValueError(
                f"time value cannot be null when type is '{self.type}' unless start/end are set"
            )
        return self


class IntentPlanDTO(BaseModel):
    model_config = ConfigDict(extra="forbid")

    domain: IntentPlanDomain
    mode: Mode = "info"
    operation: IntentPlanOperation = "count"
    time_scope: TimeScopeDTO
    filters: Dict[str, Any] = Field(default_factory=dict)
