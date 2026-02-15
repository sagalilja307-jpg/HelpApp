"""Pure domain models for proposals - no external dependencies"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import uuid4


class ProposalType(str, Enum):
    create_reminder = "create_reminder"
    schedule_timeblock = "schedule_timeblock"
    follow_up = "follow_up"


class ProposalStatus(str, Enum):
    pending = "pending"
    accepted = "accepted"
    dismissed = "dismissed"


@dataclass
class Proposal:
    proposal_type: ProposalType
    summary: str
    status: ProposalStatus = ProposalStatus.pending
    id: str = field(default_factory=lambda: str(uuid4()))
    details: Dict[str, Any] = field(default_factory=dict)
    why: Dict[str, Any] = field(default_factory=dict)
    actions: Dict[str, Any] = field(default_factory=dict)
    related_item_ids: List[str] = field(default_factory=list)
    expires_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
