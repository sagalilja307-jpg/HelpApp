from zoneinfo import ZoneInfo

from helpershelp.application.query.data_intent_router import DataIntentRouter


def test_router_explicit_date_resolves_day_window():
    router = DataIntentRouter(timezone_name="Europe/Stockholm")
    payload = router.route(query="Visa mina möten den 19/3/2026", language="sv")

    assert payload["domain"] == "calendar"
    timeframe = payload.get("timeframe")
    assert timeframe is not None
    assert timeframe["granularity"] == "day"

    start = timeframe["start"].astimezone(ZoneInfo("Europe/Stockholm"))
    end = timeframe["end"].astimezone(ZoneInfo("Europe/Stockholm"))
    assert start.date().isoformat() == "2026-03-19"
    assert end.date().isoformat() == "2026-03-19"


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
    filters = payload.get("filters") or {}
    assert isinstance(filters.get("suggested_domains"), list)
