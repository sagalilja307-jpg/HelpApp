from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import Optional


_DOW_EN = {
    "mon": 0,
    "monday": 0,
    "tue": 1,
    "tues": 1,
    "tuesday": 1,
    "wed": 2,
    "wednesday": 2,
    "thu": 3,
    "thurs": 3,
    "thursday": 3,
    "fri": 4,
    "friday": 4,
    "sat": 5,
    "saturday": 5,
    "sun": 6,
    "sunday": 6,
}

_DOW_SV = {
    "mån": 0,
    "måndag": 0,
    "tis": 1,
    "tisdag": 1,
    "ons": 2,
    "onsdag": 2,
    "tor": 3,
    "torsdag": 3,
    "fre": 4,
    "fredag": 4,
    "lör": 5,
    "lördag": 5,
    "sön": 6,
    "söndag": 6,
}


def _next_weekday(now: datetime, weekday: int) -> datetime:
    days_ahead = (weekday - now.weekday()) % 7
    if days_ahead == 0:
        days_ahead = 7
    return (now + timedelta(days=days_ahead)).replace(hour=9, minute=0, second=0, microsecond=0)


def extract_due_at(text: str, now: datetime) -> Optional[datetime]:
    """
    Best-effort due date extraction for proposal suggestions.
    Supports:
    - ISO date: YYYY-MM-DD
    - relative: today/tomorrow + Swedish idag/imorgon
    - weekdays: (by) Friday / senast fredag
    """
    if not text:
        return None
    t = text.strip()

    m = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", t)
    if m:
        try:
            return datetime.fromisoformat(m.group(1)).replace(hour=17, minute=0, second=0, microsecond=0)
        except Exception:
            pass

    low = t.lower()
    if re.search(r"\b(today|idag)\b", low):
        return now.replace(hour=17, minute=0, second=0, microsecond=0)
    if re.search(r"\b(tomorrow|imorgon)\b", low):
        return (now + timedelta(days=1)).replace(hour=17, minute=0, second=0, microsecond=0)

    # weekday mentions
    for token, wd in {**_DOW_EN, **_DOW_SV}.items():
        if re.search(rf"\b{re.escape(token)}\b", low):
            return _next_weekday(now, wd)

    return None
