from __future__ import annotations

from typing import Dict, Literal, Optional, List, Any
from pydantic import BaseModel, Field

Domain = Literal[
    "calendar",
    "reminders",
    "mail",
    "notes",
    "files",
    "location",
    "photos",
    "contacts",
]

Operation = Literal["count"]  # MVP: bara count just nu

TimeIntentCategory = Literal[
    "NONE",
    "REL_TODAY",
    "REL_TOMORROW",
    "REL_YESTERDAY",
    "REL_THIS_WEEK",
    "REL_NEXT_WEEK",
    "REL_LAST_WEEK",
    "REL_THIS_MONTH",
    "REL_NEXT_MONTH",
    "REL_LAST_N_UNITS",
    "ABS_DATE_SINGLE",
]

Granularity = Literal["day", "week", "month", "custom"]


class TimeIntentDTO(BaseModel):
    category: TimeIntentCategory
    payload: Optional[Dict[str, Any]] = None


class TimeframeDTO(BaseModel):
    start: str = Field(..., description="UTC ISO8601 datetime")
    end: str = Field(..., description="UTC ISO8601 datetime")
    granularity: Granularity


class IntentPlanDTO(BaseModel):
    domain: Optional[Domain] = None
    operation: Operation
    time_intent: TimeIntentDTO
    timeframe: Optional[TimeframeDTO] = None  # efter policy bör den alltid vara satt
    needs_clarification: bool = False
    suggestions: List[Domain] = []
