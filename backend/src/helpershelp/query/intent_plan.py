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
    "exists",
    "sum",
    "latest",
]
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

    @model_validator(mode="after")
    def validate_value_required(self) -> "TimeScopeDTO":
        if self.type != "all" and self.value is None:
            raise ValueError(f"time value cannot be null when type is '{self.type}'")
        return self


class IntentPlanDTO(BaseModel):
    model_config = ConfigDict(extra="forbid")

    domain: Domain
    mode: Mode = "info"
    operation: Operation = "count"
    time_scope: TimeScopeDTO
    filters: Dict[str, Any] = Field(default_factory=dict)

