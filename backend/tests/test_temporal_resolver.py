from datetime import datetime, timezone

from helpershelp.application.analytics.intent_parser import (
    CALENDAR_LEAST_LOADED_DAY_INTENT,
    CALENDAR_SPECIFIC_DAY_INTENT,
)
from helpershelp.application.analytics.temporal.resolver import TemporalResolver


def test_resolve_specific_day_keywords():
    resolver = TemporalResolver(timezone_name="Europe/Stockholm")
    now = datetime(2026, 2, 17, 12, 0, tzinfo=timezone.utc)

    today = resolver.resolve("Vad gör jag idag?", CALENDAR_SPECIFIC_DAY_INTENT, now=now)
    assert today.start.date().isoformat() == "2026-02-17"
    assert today.granularity == "day"

    yesterday = resolver.resolve("Vad gjorde jag igår?", CALENDAR_SPECIFIC_DAY_INTENT, now=now)
    assert yesterday.start.date().isoformat() == "2026-02-16"

    tomorrow = resolver.resolve("Vad gör jag imorgon?", CALENDAR_SPECIFIC_DAY_INTENT, now=now)
    assert tomorrow.start.date().isoformat() == "2026-02-18"


def test_resolve_specific_day_ddmm_with_verb_inference():
    resolver = TemporalResolver(timezone_name="Europe/Stockholm")
    now = datetime(2026, 2, 17, 12, 0, tzinfo=timezone.utc)

    future = resolver.resolve("Vad gör jag den 19/3?", CALENDAR_SPECIFIC_DAY_INTENT, now=now)
    assert future.start.date().isoformat() == "2026-03-19"

    past = resolver.resolve("Vad gjorde jag den 19/1?", CALENDAR_SPECIFIC_DAY_INTENT, now=now)
    assert past.start.date().isoformat() == "2026-01-19"


def test_resolve_week_window_for_least_loaded_day():
    resolver = TemporalResolver(timezone_name="Europe/Stockholm")
    now = datetime(2026, 2, 17, 12, 0, tzinfo=timezone.utc)

    current_week = resolver.resolve(
        "Vilken dag den här veckan är minst belastad?",
        CALENDAR_LEAST_LOADED_DAY_INTENT,
        now=now,
    )
    assert current_week.start.date().isoformat() == "2026-02-16"
    assert current_week.end.date().isoformat() == "2026-02-22"
    assert current_week.granularity == "week"

    last_week = resolver.resolve(
        "Vilken dag förra veckan var minst belastad?",
        CALENDAR_LEAST_LOADED_DAY_INTENT,
        now=now,
    )
    assert last_week.start.date().isoformat() == "2026-02-09"
    assert last_week.end.date().isoformat() == "2026-02-15"
