from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import uuid4

from pydantic import BaseModel, Field

from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.domain.models import (
    UnifiedItemType as DomainUnifiedItemType,
    ProposalType as DomainProposalType,
    ProposalStatus as DomainProposalStatus,
    EdgeType as DomainEdgeType,
)

# Re-export enums from domain for backward compatibility
UnifiedItemType = DomainUnifiedItemType
ProposalType = DomainProposalType
ProposalStatus = DomainProposalStatus
EdgeType = DomainEdgeType


class Person(BaseModel):
    name: Optional[str] = None
    address: str


class ExternalRef(BaseModel):
    provider: str
    provider_id: str
    url: Optional[str] = None


class Provenance(BaseModel):
    derived_from_ids: List[str] = Field(default_factory=list)
    method: str = "unknown"
    confidence: float = 1.0


class UnifiedItem(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    source: str
    type: UnifiedItemType

    title: str = ""
    body: str = ""

    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)

    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    due_at: Optional[datetime] = None

    people: List[Person] = Field(default_factory=list)
    status: Dict[str, Any] = Field(default_factory=dict)

    external_ref: Optional[ExternalRef] = None
    provenance: Optional[Provenance] = None


class ItemEdge(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    from_item_id: str
    to_item_id: str
    edge_type: EdgeType
    score: float = 0.0
    reasons: List[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=utcnow)


class Proposal(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    proposal_type: ProposalType
    status: ProposalStatus = ProposalStatus.pending
    summary: str

    details: Dict[str, Any] = Field(default_factory=dict)
    why: Dict[str, Any] = Field(default_factory=dict)
    actions: Dict[str, Any] = Field(default_factory=dict)

    related_item_ids: List[str] = Field(default_factory=list)

    expires_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class DashboardResponse(BaseModel):
    now: datetime
    important_now: List[UnifiedItem]
    upcoming: List[UnifiedItem]
    proposals: List[Proposal]


class IngestRequest(BaseModel):
    items: List[UnifiedItem]


class SyncGmailRequest(BaseModel):
    access_token: str
    days: int = 90
    max_results: int = 50


class SyncGCalRequest(BaseModel):
    access_token: str
    days_forward: int = 14
    days_back: int = 7
    max_results: int = 250


class ProposalDecisionRequest(BaseModel):
    user_edits: Dict[str, Any] = Field(default_factory=dict)


class SettingsResponse(BaseModel):
    settings: Dict[str, Any]


class SettingsUpdateRequest(BaseModel):
    settings: Dict[str, Any]


class SupportSettingsResponse(BaseModel):
    support_level: int
    paused: bool
    adaptation_enabled: bool
    daily_caps: Dict[str, int]
    time_critical_window_hours: int
    effective_policy: Dict[str, Any]


class SupportSettingsUpdateRequest(BaseModel):
    support_level: Optional[int] = None
    paused: Optional[bool] = None
    adaptation_enabled: Optional[bool] = None


class LearningPattern(BaseModel):
    key: str
    value: Any


class LearningEvent(BaseModel):
    id: str
    event_type: str
    payload: Dict[str, Any]
    created_at: datetime


class LearningSettingsResponse(BaseModel):
    adaptation_enabled: bool
    patterns: List[LearningPattern]
    events: List[LearningEvent]


class LearningPauseRequest(BaseModel):
    paused: bool


class LearningResetResponse(BaseModel):
    removed_keys: List[str]
    removed_count: int
