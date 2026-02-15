"""Mail port - abstract interface for mail operations"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional


@dataclass
class MailMessage:
    """Represents a mail message"""
    id: str
    thread_id: Optional[str]
    subject: str
    body: str
    sender: str
    recipients: List[str]
    timestamp: datetime
    is_read: bool
    is_replied: bool


class MailPort(ABC):
    """Abstract interface for mail provider operations"""

    @abstractmethod
    def fetch_messages(
        self,
        access_token: str,
        max_results: int = 50,
        days: int = 90,
        query: Optional[str] = None,
    ) -> List[MailMessage]:
        """Fetch mail messages from provider"""
        pass

    @abstractmethod
    def send_message(
        self,
        access_token: str,
        to: List[str],
        subject: str,
        body: str,
        thread_id: Optional[str] = None,
    ) -> str:
        """Send a mail message, returns message ID"""
        pass
