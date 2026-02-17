from __future__ import annotations

import os
import re
from dataclasses import dataclass
from datetime import datetime, time, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from helpershelp.application.analytics.intent_parser import (
    CALENDAR_LEAST_LOADED_DAY_INTENT,
    CALENDAR_SPECIFIC_DAY_INTENT,
)


@dataclass(frozen=True)
class TimeWindow:
    start: datetime
    end: datetime
    granularity: str


class TemporalResolver:
    """Resolve relative/explicit dates to deterministic time windows."""

    _explicit_day_pattern = re.compile(r"\b(?:den\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", re.IGNORECASE)

    _past_markers = ("gjorde", "hade", "var", "did i")
    _future_markers = ("gör", "ska", "kommer", "am i doing")

    def __init__(self, timezone_name: Optional[str] = None):
        configured = timezone_name or os.getenv("HELPERSHELP_TIMEZONE", "Europe/Stockholm")
        try:
            self._timezone = ZoneInfo(configured)
        except Exception:
            self._timezone = ZoneInfo("Europe/Stockholm")

    @property
    def timezone(self) -> ZoneInfo:
        return self._timezone

    def resolve(self, query: str, intent_id: str, now: Optional[datetime] = None) -> TimeWindow:
        local_now = self._to_local(now or datetime.now(timezone.utc))
        if intent_id == CALENDAR_SPECIFIC_DAY_INTENT:
            return self.resolve_specific_day(query, now=local_now)
        if intent_id == CALENDAR_LEAST_LOADED_DAY_INTENT:
            return self.resolve_week(query, now=local_now)
        return self.resolve_week(query, now=local_now)

    def resolve_specific_day(self, query: str, now: Optional[datetime] = None) -> TimeWindow:
        local_now = self._to_local(now or datetime.now(timezone.utc))
        normalized = (query or "").strip().lower()

        if "igår" in normalized:
            target_date = (local_now - timedelta(days=1)).date()
        elif "imorgon" in normalized:
            target_date = (local_now + timedelta(days=1)).date()
        elif "idag" in normalized:
            target_date = local_now.date()
        else:
            target_date = self._resolve_explicit_date(normalized, local_now)

        return self._day_window(target_date)

    def resolve_week(self, query: str, now: Optional[datetime] = None) -> TimeWindow:
        local_now = self._to_local(now or datetime.now(timezone.utc))
        normalized = (query or "").strip().lower()

        today = local_now.date()
        week_start = today - timedelta(days=today.weekday())

        if "förra veckan" in normalized or "last week" in normalized:
            week_start -= timedelta(days=7)

        week_end = week_start + timedelta(days=6)
        start = datetime.combine(week_start, time.min, tzinfo=self._timezone)
        end = datetime.combine(week_end, time.max, tzinfo=self._timezone)
        return TimeWindow(start=start, end=end, granularity="week")

    def _resolve_explicit_date(self, normalized_query: str, local_now: datetime):
        match = self._explicit_day_pattern.search(normalized_query)
        if not match:
            return local_now.date()

        day = int(match.group(1))
        month = int(match.group(2))
        year_group = match.group(3)

        if year_group:
            year = int(year_group)
            if year < 100:
                year += 2000
            return self._safe_date(year=year, month=month, day=day, fallback=local_now.date())

        if any(marker in normalized_query for marker in self._past_markers):
            return self._latest_past_date(day=day, month=month, local_now=local_now)

        if any(marker in normalized_query for marker in self._future_markers):
            return self._nearest_future_date(day=day, month=month, local_now=local_now)

        # Default in Fas 0.5: nearest future date.
        return self._nearest_future_date(day=day, month=month, local_now=local_now)

    @staticmethod
    def _safe_date(year: int, month: int, day: int, fallback):
        try:
            return datetime(year=year, month=month, day=day).date()
        except ValueError:
            return fallback

    def _nearest_future_date(self, day: int, month: int, local_now: datetime):
        this_year = self._safe_date(year=local_now.year, month=month, day=day, fallback=local_now.date())
        if this_year >= local_now.date():
            return this_year
        return self._safe_date(year=local_now.year + 1, month=month, day=day, fallback=this_year)

    def _latest_past_date(self, day: int, month: int, local_now: datetime):
        this_year = self._safe_date(year=local_now.year, month=month, day=day, fallback=local_now.date())
        if this_year <= local_now.date():
            return this_year
        return self._safe_date(year=local_now.year - 1, month=month, day=day, fallback=this_year)

    def _day_window(self, target_date) -> TimeWindow:
        start = datetime.combine(target_date, time.min, tzinfo=self._timezone)
        end = datetime.combine(target_date, time.max, tzinfo=self._timezone)
        return TimeWindow(start=start, end=end, granularity="day")

    def _to_local(self, dt: datetime) -> datetime:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(self._timezone)
