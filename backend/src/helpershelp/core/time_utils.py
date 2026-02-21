from __future__ import annotations

from datetime import datetime, timezone, tzinfo
from typing import Optional

UTC = timezone.utc


def utcnow() -> datetime:
    """
    Return a naive UTC timestamp for legacy storage paths.

    New code should prefer `utcnow_aware()` and explicit timezone handling.
    """
    return utcnow_aware().replace(tzinfo=None)


def utcnow_aware() -> datetime:
    """Return current UTC timestamp with explicit timezone."""
    return datetime.now(UTC)


def ensure_utc(value: datetime, assume_tz: tzinfo = UTC) -> datetime:
    """Normalize any datetime into timezone-aware UTC."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=assume_tz)
    return value.astimezone(UTC)


def parse_iso_datetime(value: Optional[str | datetime], assume_tz: tzinfo = UTC) -> Optional[datetime]:
    """Parse ISO8601-like input and normalize to timezone-aware UTC."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return ensure_utc(value, assume_tz=assume_tz)
    if not isinstance(value, str) or not value:
        return None

    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None

    return ensure_utc(parsed, assume_tz=assume_tz)


def format_iso8601(value: datetime) -> str:
    """Render datetime as explicit UTC ISO8601 with Z suffix."""
    return ensure_utc(value).isoformat().replace("+00:00", "Z")
