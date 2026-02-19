from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Callable, Dict, Literal, Optional
from zoneinfo import ZoneInfo

from helpershelp.domain.value_objects.time_utils import ensure_utc, utcnow_aware

TimeIntentCategory = Literal[
    "NONE",
    "REL_TODAY",
    "REL_TOMORROW",
    "REL_YESTERDAY",
    "REL_THIS_WEEK",
    "REL_NEXT_WEEK",
    "REL_LAST_WEEK",
    "REL_THIS_MONTH",
    "REL_NEXT_MONTH",
    "REL_LAST_N_UNITS",
    "ABS_DATE_SINGLE",
]

Granularity = Literal["day", "week", "month", "custom"]


@dataclass(frozen=True)
class TimeIntent:
    category: TimeIntentCategory
    payload: Optional[Dict[str, object]] = None  # MVP: mostly None


@dataclass(frozen=True)
class TimeParseResult:
    time_intent: TimeIntent
    timeframe: Optional[Dict[str, object]]  # {"start": dt_utc, "end": dt_utc, "granularity": str}


class QueryTimeframeResolver:
    """
    Time parsing + UTC window construction.

    Returns:
      - time_intent.category (locked taxonomy)
      - timeframe (start/end UTC) when deterministically resolvable
      - None timeframe for NONE (policy will decide default range per domain)
    """

    _EXPLICIT_DATE = re.compile(
        r"\b(?:den\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", re.IGNORECASE
    )
    _LAST_DAYS = re.compile(
        r"\b(?:last|senaste)\s+(\d{1,3})\s+(?:days|dagar)\b", re.IGNORECASE
    )

    def __init__(
        self,
        timezone_name: str,
        now_provider: Optional[Callable[[], datetime]] = None,
    ) -> None:
        self._tz = ZoneInfo(timezone_name)
        self._now_provider = now_provider or utcnow_aware

    def resolve(self, text: str) -> TimeParseResult:
        q = (text or "").strip().lower()

        now_local = ensure_utc(self._now_provider()).astimezone(self._tz)
        today = now_local.date()

        # 1) Relative day
        if "idag" in q or "today" in q:
            return self._result("REL_TODAY", self._day_window(today))
        if "imorgon" in q or "tomorrow" in q:
            return self._result("REL_TOMORROW", self._day_window(today + timedelta(days=1)))
        if "igår" in q or "yesterday" in q:
            return self._result("REL_YESTERDAY", self._day_window(today - timedelta(days=1)))

        # 2) Week
        if "denna vecka" in q or "this week" in q or "veckan" in q:
            return self._result("REL_THIS_WEEK", self._week_window(today))
        if "nästa vecka" in q or "next week" in q:
            return self._result("REL_NEXT_WEEK", self._week_window(today + timedelta(days=7)))
        if "förra veckan" in q or "last week" in q:
            return self._result("REL_LAST_WEEK", self._week_window(today - timedelta(days=7)))

        # 3) Month
        if "denna månad" in q or "this month" in q:
            return self._result("REL_THIS_MONTH", self._month_window(today))
        if "nästa månad" in q or "next month" in q:
            month_start = today.replace(day=1)
            next_month_start = (month_start + timedelta(days=32)).replace(day=1)
            return self._result("REL_NEXT_MONTH", self._month_window(next_month_start))

        # 4) Last N days
        m = self._LAST_DAYS.search(q)
        if m:
            n = max(1, min(365, int(m.group(1))))
            start_local = now_local - timedelta(days=n)
            end_local = now_local
            tf = self._window(start_local, end_local, "custom")
            return TimeParseResult(time_intent=TimeIntent("REL_LAST_N_UNITS", {"n": n, "unit": "day"}), timeframe=tf)

        # 5) Explicit date dd/mm[/yyyy]
        m = self._EXPLICIT_DATE.search(q)
        if m:
            day = int(m.group(1))
            month = int(m.group(2))
            year_raw = m.group(3)

            year = today.year
            if year_raw:
                year = int(year_raw)
                if year < 100:
                    year += 2000

            try:
                d = date(year=year, month=month, day=day)
            except ValueError:
                return self._none()

            tf = self._day_window(d)
            return TimeParseResult(time_intent=TimeIntent("ABS_DATE_SINGLE", {"date": d.isoformat()}), timeframe=tf)

        # 6) NONE
        return self._none()

    # -------- internals --------

    def _none(self) -> TimeParseResult:
        return TimeParseResult(time_intent=TimeIntent("NONE", None), timeframe=None)

    def _result(self, category: TimeIntentCategory, timeframe: Dict[str, object]) -> TimeParseResult:
        return TimeParseResult(time_intent=TimeIntent(category, None), timeframe=timeframe)

    def _day_window(self, d: date) -> Dict[str, object]:
        start_local = datetime.combine(d, time.min, tzinfo=self._tz)
        end_local = start_local + timedelta(days=1)  # half-open
        return self._window(start_local, end_local, "day")

    def _week_window(self, d: date) -> Dict[str, object]:
        week_start = d - timedelta(days=d.weekday())
        start_local = datetime.combine(week_start, time.min, tzinfo=self._tz)
        end_local = start_local + timedelta(days=7)  # half-open
        return self._window(start_local, end_local, "week")

    def _month_window(self, d: date) -> Dict[str, object]:
        month_start = d.replace(day=1)
        start_local = datetime.combine(month_start, time.min, tzinfo=self._tz)
        next_month_start = (month_start + timedelta(days=32)).replace(day=1)
        end_local = datetime.combine(next_month_start, time.min, tzinfo=self._tz)  # half-open
        return self._window(start_local, end_local, "month")

    def _window(self, start_local: datetime, end_local: datetime, granularity: Granularity) -> Dict[str, object]:
        return {
            "start": ensure_utc(start_local),
            "end": ensure_utc(end_local),
            "granularity": granularity,
        }

