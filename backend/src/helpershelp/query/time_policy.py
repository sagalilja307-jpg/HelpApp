from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Dict, Optional, cast
from zoneinfo import ZoneInfo

from helpershelp.query.intent_plan import Domain
from helpershelp.core.time_utils import ensure_utc, utcnow_aware
from helpershelp.query.timeframe_resolver import TimeParseResult


@dataclass(frozen=True)
class TimePolicyConfig:
    timezone_name: str = "Europe/Stockholm"

    # Default windows when user didn't mention time (NONE)
    default_past_days_mail: int = 30
    default_past_days_notes: int = 365
    default_past_days_files: int = 365
    default_past_days_photos: int = 90
    default_past_days_location: int = 30
    default_past_days_contacts: int = 3650  # basically "all", but bounded

    default_future_days_calendar: int = 30
    default_future_days_reminders: int = 30

    # Hard clamps to avoid “all time” scans
    clamp_max_past_days: int = 3650
    clamp_max_future_days: int = 365


class TimePolicy:
    """
    Applies domain-specific policy:
      - If TimeIntent is NONE => pick a default timeframe per domain
      - Otherwise => optionally clamp overly large windows
    """

    def __init__(self, config: Optional[TimePolicyConfig] = None, now_provider=utcnow_aware):
        self.cfg = config or TimePolicyConfig()
        self._tz = ZoneInfo(self.cfg.timezone_name)
        self._now_provider = now_provider

    def apply(self, domain: Domain, parsed: TimeParseResult) -> Dict[str, object]:
        """
        Returns timeframe dict: {"start": dt_utc, "end": dt_utc, "granularity": "..."}
        Always returns a timeframe after policy.
        """
        if parsed.time_intent.category == "NONE" or parsed.timeframe is None:
            return self._default_window(domain)

        # We have an explicit timeframe from the resolver; clamp it if needed.
        return self._clamp(domain, parsed.timeframe)

    # ---- internals ----

    def _now_local(self) -> datetime:
        return ensure_utc(self._now_provider()).astimezone(self._tz)

    def _default_window(self, domain: Domain) -> Dict[str, object]:
        now_local = self._now_local()

        if domain == "calendar":
            return self._window(now_local, now_local + timedelta(days=self.cfg.default_future_days_calendar), "custom")

        if domain == "reminders":
            # reminders often include slightly in past (overdue) + future
            start = now_local - timedelta(days=7)
            end = now_local + timedelta(days=self.cfg.default_future_days_reminders)
            return self._window(start, end, "custom")

        if domain == "mail":
            return self._window(now_local - timedelta(days=self.cfg.default_past_days_mail), now_local, "custom")

        if domain == "notes":
            return self._window(now_local - timedelta(days=self.cfg.default_past_days_notes), now_local, "custom")

        if domain == "memory":
            return self._window(now_local - timedelta(days=self.cfg.default_past_days_notes), now_local, "custom")

        if domain == "files":
            return self._window(now_local - timedelta(days=self.cfg.default_past_days_files), now_local, "custom")

        if domain == "photos":
            return self._window(now_local - timedelta(days=self.cfg.default_past_days_photos), now_local, "custom")

        if domain == "location":
            return self._window(now_local - timedelta(days=self.cfg.default_past_days_location), now_local, "custom")

        if domain == "contacts":
            return self._window(now_local - timedelta(days=self.cfg.default_past_days_contacts), now_local, "custom")

        # safe fallback
        return self._window(now_local - timedelta(days=30), now_local, "custom")

    def _clamp(self, domain: Domain, timeframe: Dict[str, object]) -> Dict[str, object]:
        # Clamp by absolute maximums (simple MVP, domain-agnostic)
        start_utc = ensure_utc(cast(datetime, timeframe["start"]))
        end_utc = ensure_utc(cast(datetime, timeframe["end"]))

        start_local = start_utc.astimezone(self._tz)
        end_local = end_utc.astimezone(self._tz)

        now_local = self._now_local()

        # Limit past range
        min_start_local = now_local - timedelta(days=self.cfg.clamp_max_past_days)
        if start_local < min_start_local:
            start_local = min_start_local

        # Limit future range
        max_end_local = now_local + timedelta(days=self.cfg.clamp_max_future_days)
        if end_local > max_end_local:
            end_local = max_end_local

        granularity = cast(str, timeframe.get("granularity", "custom"))
        return self._window(start_local, end_local, granularity)

    def _window(self, start_local: datetime, end_local: datetime, granularity: str) -> Dict[str, object]:
        return {
            "start": ensure_utc(start_local),
            "end": ensure_utc(end_local),
            "granularity": granularity,
        }
