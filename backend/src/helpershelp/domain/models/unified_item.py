"""Pure domain models - no external dependencies (FastAPI, Pydantic, etc.)"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import uuid4


class UnifiedItemType(str, Enum):
    email = "email"
    event = "event"
    task = "task"
    reminder = "reminder"
    note = "note"
    contact = "contact"
    photo = "photo"
    file = "file"
    location = "location"


class EdgeType(str, Enum):
    related_to = "related_to"
    about_same = "about_same"
    blocks_time_for = "blocks_time_for"


@dataclass
class Person:
    address: str
    name: Optional[str] = None


@dataclass
class ExternalRef:
    provider: str
    provider_id: str
    url: Optional[str] = None


@dataclass
class Provenance:
    method: str = "unknown"
    confidence: float = 1.0
    derived_from_ids: List[str] = field(default_factory=list)


@dataclass
class UnifiedItem:
    source: str
    type: UnifiedItemType
    title: str = ""
    body: str = ""
    id: str = field(default_factory=lambda: str(uuid4()))
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    people: List[Person] = field(default_factory=list)
    status: Dict[str, Any] = field(default_factory=dict)
    external_ref: Optional[ExternalRef] = None
    provenance: Optional[Provenance] = None


@dataclass
class ItemEdge:
    from_item_id: str
    to_item_id: str
    edge_type: EdgeType
    score: float = 0.0
    id: str = field(default_factory=lambda: str(uuid4()))
    reasons: List[str] = field(default_factory=list)
    created_at: Optional[datetime] = None
