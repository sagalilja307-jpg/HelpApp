from datetime import datetime
from email.utils import parseaddr
from typing import Dict, Any

from helpershelp.core.time_utils import parse_iso_datetime
from helpershelp.mail.content_object import ContentObject, MailSender


def _extract_domain(email_address: str) -> str | None:
    if "@" not in email_address:
        return None
    return email_address.split("@", 1)[1].lower()


def mail_event_to_content_object(raw_mail: Dict[str, Any]) -> ContentObject:
    """
    Converts raw provider mail data into a ContentObject.
    No interpretation. No filtering. No prioritisation.
    """

    name, address = parseaddr(raw_mail.get("from", ""))

    sender = MailSender(
        address=address,
        name=name or None,
        domain=_extract_domain(address)
    )

    return ContentObject(
        id=raw_mail["id"],
        source="email",

        subject=raw_mail.get("subject", ""),
        body=raw_mail.get("body", ""),

        sender=sender,

        received_at=_parse_datetime(raw_mail["received_at"]),

        thread_id=raw_mail.get("thread_id"),
        is_replied=bool(raw_mail.get("is_replied", False))
    )


def _parse_datetime(value: str | datetime) -> datetime:
    parsed = parse_iso_datetime(value)
    if parsed is not None:
        return parsed
    if isinstance(value, datetime):
        return value
    raise ValueError(f"Invalid datetime value: {value}")
