from dataclasses import dataclass
from datetime import datetime
from typing import Optional


@dataclass(frozen=True)
class MailSender:
    """
    Raw sender metadata.
    Relation is interpreted in the app – never here.
    """
    address: str
    name: Optional[str]
    domain: Optional[str]


@dataclass(frozen=True)
class ContentObject:
    """
    Canonical content contract between backend and app.
    Backend provides facts only.
    App decides meaning.
    """

    # Identity
    id: str
    source: str  # e.g. "email"

    # Content
    subject: str
    body: str

    # Relation
    sender: MailSender

    # Time
    received_at: datetime

    # Thread / status
    thread_id: Optional[str]
    is_replied: bool
