from datetime import timedelta
from typing import List, Optional, Dict

from helpershelp.assistant.time_utils import utcnow
from helpershelp.retrieval.content_object import ContentObject
from helpershelp.mail.mail_event import mail_event_to_content_object


class MailQueryService:
    """
    Mail source for universal retrieval pipeline.
    
    Handles:
    - Fetching mail from provider
    - Normalizing to ContentObject
    - Supporting time-range filtering
    
    This is ONE source in the retrieval system.
    Not responsible for ranking or filtering – that's RetrievalCoordinator.
    """

    def __init__(self, mail_provider):
        """
        mail_provider must expose:
        - fetch_all() -> list[dict]
        Raw provider format only.
        """
        self.mail_provider = mail_provider

    def fetch(self, time_range: Optional[Dict] = None, data_filter: Optional[Dict] = None) -> List[ContentObject]:
        """
        Fetch mail, optionally filtered by time range and metadata filters.
        
        Args:
            time_range: Dict with "days" key, e.g. {"days": 90}
            data_filter: Dict with "filterType" and "appliesTo" keys
                e.g. {"filterType": "unread", "appliesTo": ["email"]}
        
        Returns:
            List of ContentObjects (normalized)
        """
        mails = self.mail_provider.fetch_all()
        
        # Calculate cutoff if time_range specified
        since = None
        if time_range and "days" in time_range:
            since = utcnow() - timedelta(days=time_range["days"])
        
        results: list[ContentObject] = []
        
        for raw in mails:
            received_at = _parse_datetime(raw.get("received_at"))
            
            # Filter by time if specified
            if since and received_at < since:
                continue
            
            # Apply metadata filter if specified
            if data_filter:
                filter_type = data_filter.get("filterType")
                applies_to = data_filter.get("appliesTo", [])
                
                # Only apply filter if "email" is in appliesTo
                if "email" in applies_to:
                    if filter_type == "unread" and raw.get("is_read", False):
                        continue
                    elif filter_type == "unanswered" and raw.get("is_replied", False):
                        continue
            
            results.append(mail_event_to_content_object(raw))
        
        return results

    def unanswered(
        self,
        since: Optional[datetime] = None,
        max_results: int = 50
    ) -> List[ContentObject]:
        """Legacy method – kept for backwards compatibility."""
        mails = self.mail_provider.fetch_all()
        results: list[ContentObject] = []

        for raw in mails:
            if raw.get("is_replied", False):
                continue

            received_at = _parse_datetime(raw.get("received_at"))
            if since and received_at < since:
                continue

            results.append(mail_event_to_content_object(raw))

            if len(results) >= max_results:
                break

        return results

    def from_domain(
        self,
        domain: str,
        max_results: int = 50
    ) -> List[ContentObject]:
        """Legacy method – kept for backwards compatibility."""
        mails = self.mail_provider.fetch_all()
        results: list[ContentObject] = []

        for raw in mails:
            sender = raw.get("from", "")
            if f"@{domain}" not in sender.lower():
                continue

            results.append(mail_event_to_content_object(raw))

            if len(results) >= max_results:
                break

        return results

    def recent(
        self,
        days: int = 7,
        max_results: int = 50
    ) -> List[ContentObject]:
        """Legacy method – kept for backwards compatibility."""
        since = utcnow() - timedelta(days=days)
        mails = self.mail_provider.fetch_all()
        results: list[ContentObject] = []

        for raw in mails:
            received_at = _parse_datetime(raw.get("received_at"))
            if received_at < since:
                continue

            results.append(mail_event_to_content_object(raw))

            if len(results) >= max_results:
                break

        return results


def _parse_datetime(value):
    if isinstance(value, datetime):
        return value
    return datetime.fromisoformat(value)
