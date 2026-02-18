from __future__ import annotations

import re
from datetime import date, datetime, time, timedelta
from typing import Callable, Dict, Optional
from zoneinfo import ZoneInfo

from helpershelp.domain.value_objects.time_utils import ensure_utc, utcnow_aware

_ALLOWED_GRANULARITY = {"day", "week", "month", "custom"}


class QueryTimeframeResolver:
    _EXPLICIT_DATE = re.compile(r"\b(?:den\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", re.IGNORECASE)
    _LAST_DAYS = re.compile(r"\b(?:last|senaste)\s+(\d{1,3})\s+(?:days|dagar)\b", re.IGNORECASE)

    def __init__(
        self,
        timezone_name: str,
        now_provider: Optional[Callable[[], datetime]] = None,
    ) -> None:
        self._timezone = ZoneInfo(timezone_name)
        self._now_provider = now_provider or utcnow_aware

    def resolve(self, normalized_query: str) -> Optional[Dict[str, object]]:
        now_local = ensure_utc(self._now_provider()).astimezone(self._timezone)
        today = now_local.date()

        if "idag" in normalized_query or "today" in normalized_query:
            return self._day_window(today)
        if "igår" in normalized_query or "yesterday" in normalized_query:
            return self._day_window(today - timedelta(days=1))
        if "imorgon" in normalized_query or "tomorrow" in normalized_query:
            return self._day_window(today + timedelta(days=1))

        if "denna vecka" in normalized_query or "this week" in normalized_query or "veckan" in normalized_query:
            return self._week_window(today)
        if "nästa vecka" in normalized_query or "next week" in normalized_query:
            return self._week_window(today + timedelta(days=7))
        if "förra veckan" in normalized_query or "last week" in normalized_query:
            return self._week_window(today - timedelta(days=7))

        if "denna månad" in normalized_query or "this month" in normalized_query:
            return self._month_window(today)
        if "nästa månad" in normalized_query or "next month" in normalized_query:
            next_month = (today.replace(day=1) + timedelta(days=32)).replace(day=1)
            return self._month_window(next_month)

        last_days_match = self._LAST_DAYS.search(normalized_query)
        if last_days_match:
            days = max(1, min(365, int(last_days_match.group(1))))
            start_local = now_local - timedelta(days=days)
            end_local = now_local
            return self._window(start_local, end_local, "custom")

        explicit = self._EXPLICIT_DATE.search(normalized_query)
        if explicit:
            day = int(explicit.group(1))
            month = int(explicit.group(2))
            year_raw = explicit.group(3)

            year = today.year
            if year_raw:
                year = int(year_raw)
                if year < 100:
                    year += 2000

            try:
                parsed_day = date(year=year, month=month, day=day)
            except ValueError:
                return None

            return self._day_window(parsed_day)

        if "senaste" in normalized_query or "recent" in normalized_query:
            return self._window(now_local - timedelta(days=30), now_local, "custom")

        return None

    def _day_window(self, day_value: date) -> Dict[str, object]:
        start_local = datetime.combine(day_value, time.min, tzinfo=self._timezone)
        end_local = datetime.combine(day_value, time.max, tzinfo=self._timezone)
        return self._window(start_local, end_local, "day")

    def _week_window(self, day_value: date) -> Dict[str, object]:
        week_start = day_value - timedelta(days=day_value.weekday())
        week_end = week_start + timedelta(days=6)
        start_local = datetime.combine(week_start, time.min, tzinfo=self._timezone)
        end_local = datetime.combine(week_end, time.max, tzinfo=self._timezone)
        return self._window(start_local, end_local, "week")

    def _month_window(self, day_value: date) -> Dict[str, object]:
        month_start = day_value.replace(day=1)
        next_month_start = (month_start + timedelta(days=32)).replace(day=1)
        month_end = next_month_start - timedelta(days=1)
        start_local = datetime.combine(month_start, time.min, tzinfo=self._timezone)
        end_local = datetime.combine(month_end, time.max, tzinfo=self._timezone)
        return self._window(start_local, end_local, "month")

    def _window(self, start_value: datetime, end_value: datetime, granularity: str) -> Dict[str, object]:
        if granularity not in _ALLOWED_GRANULARITY:
            raise ValueError(f"Unsupported granularity: {granularity}")

        return {
            "start": ensure_utc(start_value),
            "end": ensure_utc(end_value),
            "granularity": granularity,
        }
