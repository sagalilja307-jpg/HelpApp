"""
Deterministisk router som mappar användarfrågor till IntentPlanDTO-liknande DataIntent payload.
"""

from __future__ import annotations

from datetime import datetime
from typing import Callable, Dict, Optional

from helpershelp.query.intent_plan import (
    Domain,
    IntentPlanDTO,
    Operation,
    TimeScopeDTO,
    TimeScopeType,
)
from helpershelp.query.domain_classifier import DomainClassifier
from helpershelp.query.time_policy import TimePolicy, TimePolicyConfig
from helpershelp.query.timeframe_resolver import QueryTimeframeResolver, TimeIntent
from helpershelp.core.time_utils import utcnow_aware


def _map_relative_n_value(n: int) -> str:
    if n == 7:
        return "7d"
    if n == 30:
        return "30d"
    if n == 90:
        return "3m"
    if n == 365:
        return "1y"
    return f"{n}d"


def _time_scope_from_time_intent(
    time_intent: TimeIntent, _timeframe: Optional[Dict[str, object]]
) -> TimeScopeDTO:
    category = time_intent.category
    payload = time_intent.payload or {}

    scope_type: TimeScopeType = "all"
    scope_value: Optional[str] = None

    if category == "REL_TODAY":
        scope_type = "relative"
        scope_value = "today"
    elif category == "REL_TODAY_MORNING":
        scope_type = "relative"
        scope_value = "today_morning"
    elif category == "REL_TODAY_DAY":
        scope_type = "relative"
        scope_value = "today_day"
    elif category == "REL_TODAY_AFTERNOON":
        scope_type = "relative"
        scope_value = "today_afternoon"
    elif category == "REL_TODAY_EVENING":
        scope_type = "relative"
        scope_value = "today_evening"
    elif category == "REL_TOMORROW_MORNING":
        scope_type = "relative"
        scope_value = "tomorrow_morning"
    elif category in {"REL_THIS_WEEK", "REL_NEXT_WEEK", "REL_LAST_WEEK"}:
        scope_type = "relative"
        scope_value = "7d"
    elif category in {"REL_THIS_MONTH", "REL_NEXT_MONTH"}:
        scope_type = "relative"
        scope_value = "30d"
    elif category == "REL_LAST_N_UNITS":
        n = int(payload.get("n", 0))  # pyright: ignore[reportArgumentType]
        scope_type = "relative"
        scope_value = _map_relative_n_value(n)
    elif category == "ABS_DATE_SINGLE":
        scope_type = "absolute"
        scope_value = str(payload.get("date")) if payload else "unknown"
    elif category == "REL_TOMORROW":
        scope_type = "relative"
        scope_value = "tomorrow"
    elif category == "REL_YESTERDAY":
        scope_type = "relative"
        scope_value = "yesterday"
    elif category == "NONE":
        scope_type = "all"

    return TimeScopeDTO(
        type=scope_type,
        value=scope_value,
    )


def _operation_for_query(_domain: Domain, query: str) -> Operation:
    q = (query or "").lower().strip()

    # ---- Exists ----
    if (
        q.startswith("finns det")
        or q.startswith("finns det någon")
        or q.startswith("har jag några")
        or q.startswith("har jag någon")
    ):
        return "exists"

    # ---- Count ----
    if q.startswith("hur många") or "antal" in q:
        return "count"

    # ---- Sum ----
    if q.startswith("hur länge") or "hur lång tid" in q:
        return "sum"

    # ---- Latest ----
    # Only treat as 'latest' when the question is explicitly asking *when* (starts with "när")
    # e.g. "När är nästa...", "När tog jag den senaste..."
    if q.startswith("när") and any(
        k in q for k in ("nästa", "när är nästa", "senaste", "senast", "next", "last")
    ):
        return "latest"

    # ---- Explicit list phrasing ----
    if (
        q.startswith("vilka")
        or q.startswith("vad har jag")
        or q.startswith("vad är")
        or q.startswith("vad händer")
        or q.startswith("var")
    ):
        return "list"

    # ---- Search-like phrasing ----
    if any(word in q for word in ["sök", "söker", "search", "find", "hitta", "visa"]):
        return "list"

    # Safe fallback
    return "count"


class DataIntentRouter:
    def __init__(
        self,
        *,
        timezone_name: str = "Europe/Stockholm",
        now_provider: Optional[Callable[[], datetime]] = None,
    ) -> None:
        _now = now_provider or utcnow_aware

        self.domain_classifier = DomainClassifier()
        self.time_resolver = QueryTimeframeResolver(
            timezone_name=timezone_name, now_provider=_now
        )
        self.time_policy = TimePolicy(
            TimePolicyConfig(timezone_name=timezone_name), now_provider=_now
        )

    def route(self, query: str, language: str = "sv") -> Dict[str, object]:
        q = (query or "").strip()
        filters: Dict[str, object] = {}

        try:
            dom = self.domain_classifier.classify(q)
        except Exception:
            parsed = self.time_resolver.resolve(q)
            return {
                "needs_clarification": True,
                "suggestions": ["calendar", "mail"],
                "time_scope": _time_scope_from_time_intent(
                    parsed.time_intent, parsed.timeframe
                ).model_dump(mode="python"),
            }

        parsed = self.time_resolver.resolve(q)
        lower_q = q.lower()

        if dom.domain == "mail" and (
            "oläst" in lower_q or "olästa" in lower_q or "unread" in lower_q
        ):
            filters["status"] = "unread"

        # Always definitively resolve domain, default to calendar
        resolved_domain: Domain = "calendar"
        if dom.domain is not None:
            resolved_domain = dom.domain
        elif dom.suggestions:
            resolved_domain = dom.suggestions[0]

        timeframe = self.time_policy.apply(resolved_domain, parsed)
        time_scope = _time_scope_from_time_intent(parsed.time_intent, timeframe)
        operation = _operation_for_query(resolved_domain, q)

        plan = IntentPlanDTO(
            domain=resolved_domain,
            mode="info",
            operation=operation,
            time_scope=time_scope,
            filters=filters,
        )
        return plan.model_dump(mode="python")
