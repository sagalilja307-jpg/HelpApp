from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from helpershelp.application.query.data_intent_router import DataIntentRouter


def test_router_explicit_date_resolves_day_window():
    router = DataIntentRouter(timezone_name="Europe/Stockholm")
    payload = router.route(query="Visa mina möten den 19/3/2026", language="sv")

    assert payload["domain"] == "calendar"
    time_scope = payload.get("time_scope")
    assert time_scope is not None
    assert time_scope["type"] == "absolute"
    assert time_scope["value"] is None

    start = time_scope["start"].astimezone(ZoneInfo("Europe/Stockholm"))
    end = time_scope["end"].astimezone(ZoneInfo("Europe/Stockholm"))
    assert start.date().isoformat() == "2026-03-19"
    assert end.date().isoformat() == "2026-03-20"


def test_router_count_mail_unread():
    router = DataIntentRouter(timezone_name="Europe/Stockholm")
    payload = router.route(query="Hur många olästa mejl har jag?", language="sv")

    assert payload["domain"] == "mail"
    assert payload["operation"] == "count"
    filters = payload.get("filters") or {}
    assert filters.get("status") == "unread"


def test_router_ambiguity_returns_clarification():
    router = DataIntentRouter(timezone_name="Europe/Stockholm")
    payload = router.route(query="Vad händer?", language="sv")

    assert payload["domain"] == "system"
    assert payload["operation"] == "needs_clarification"
    assert payload["needs_clarification"] is True
    assert isinstance(payload.get("suggestions"), list)
    assert payload.get("clarification_message")


def test_router_relative_timeframe_is_deterministic_with_injected_now():
    fixed_now = datetime(2026, 2, 18, 12, 0, tzinfo=timezone.utc)
    router = DataIntentRouter(
        timezone_name="Europe/Stockholm",
        now_provider=lambda: fixed_now,
    )
    payload = router.route(query="Visa mina möten idag", language="sv")

    time_scope = payload.get("time_scope")
    assert time_scope is not None
    assert time_scope["type"] == "relative"
    assert time_scope["value"] == "today"
    assert time_scope["start"].tzinfo is not None
    assert time_scope["end"].tzinfo is not None

    start_local = time_scope["start"].astimezone(ZoneInfo("Europe/Stockholm"))
    end_local = time_scope["end"].astimezone(ZoneInfo("Europe/Stockholm"))
    assert start_local.date().isoformat() == "2026-02-18"
    assert end_local.date().isoformat() == "2026-02-19"


def test_router_week_time_scope_uses_allowed_relative_value():
    router = DataIntentRouter(timezone_name="Europe/Stockholm")
    payload = router.route(query="Visa kalender denna vecka", language="sv")

    time_scope = payload.get("time_scope")
    assert time_scope is not None
    assert time_scope["type"] == "relative"
    assert time_scope["value"] in {"7d", "30d", "3m", "1y", "today"}
