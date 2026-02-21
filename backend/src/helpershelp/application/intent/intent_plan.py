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
TimeScopeValue = Literal["today", "7d", "30d", "3m", "1y"]


class TimeScopeDTO(BaseModel):
    type: TimeScopeType
    value: Optional[str] = None


class IntentPlanDTO(BaseModel):
    model_config = ConfigDict(extra="forbid")

    domain: Domain
    mode: Mode = "info"
    operation: Operation = "count"
    time_scope: TimeScopeDTO
    filters: Dict[str, Any] = Field(default_factory=dict)

