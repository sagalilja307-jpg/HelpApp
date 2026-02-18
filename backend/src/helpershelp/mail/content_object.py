from dataclasses import dataclass
from datetime import datetime
from typing import Optional


@dataclass(frozen=True)
class MailSender:
    """Raw sender metadata."""

    address: str
    name: Optional[str]
    domain: Optional[str]


@dataclass(frozen=True)
class ContentObject:
    """Canonical mail/query content contract."""

    id: str
    source: str
    subject: str
    body: str
    sender: MailSender
    received_at: datetime
    thread_id: Optional[str]
    is_replied: bool
