from __future__ import annotations

"""
Deterministisk router som mappar användarfrågor till DataIntent v1.

Historik: Den fanns refererad i API-deps och tester men hade raderats.
Denna version är en tunn wrapper runt befintliga komponenter:
  - DomainClassifier (embeddings-baserad när den finns)
  - QueryTimeframeResolver + TimePolicy (samma som IntentBuilder)

Fallbacks finns för att inte krascha när embeddings‑tjänsten saknas:
  - Vid klassificeringsfel returneras clarification med suggested_domains.
  - Enkel heuristik för olästa mejl ("oläst"/"unread") sätter filters.status.

Router returnerar ett enkelt dict som backend/tests förväntar sig:
  {
    "domain": str | None,
    "operation": str,
    "time_intent": {"category": str, "payload": ...},
    "timeframe": {"start": datetime, "end": datetime, "granularity": str} | None,
    "filters": dict | None,
    "needs_clarification": bool,
    "suggestions": list[str]
  }
"""

from typing import Dict, Optional

from helpershelp.application.intent.intent_plan import TimeIntentCategory
from helpershelp.application.query.domain_classifier import DomainClassifier
from helpershelp.application.query.time_policy import TimePolicy, TimePolicyConfig
from helpershelp.application.query.timeframe_resolver import QueryTimeframeResolver
from helpershelp.domain.value_objects.time_utils import utcnow_aware


def _safe_time_intent(category: TimeIntentCategory, payload: Optional[Dict[str, object]]):
    return {"category": category, "payload": payload}


class DataIntentRouter:
    def __init__(
        self,
        *,
        timezone_name: str = "Europe/Stockholm",
        now_provider=None,
    ) -> None:
        _now = now_provider or utcnow_aware

        self.domain_classifier = DomainClassifier()
        self.time_resolver = QueryTimeframeResolver(timezone_name=timezone_name, now_provider=_now)
        self.time_policy = TimePolicy(TimePolicyConfig(timezone_name=timezone_name), now_provider=_now)

    def route(self, query: str, language: str = "sv") -> Dict[str, object]:
        q = (query or "").strip()
        filters: Dict[str, object] = {}

        try:
            dom = self.domain_classifier.classify(q)
        except Exception:
            # Embeddings kan saknas lokalt; gör ett tryggt fallback-svar
            return self._clarification_response(
                suggestions=["calendar", "mail"],
                time_intent=self.time_resolver.resolve(q).time_intent,
            )

        # Tidsintent + ev timeframe
        parsed = self.time_resolver.resolve(q)

        # Enkel heuristik för olästa mejl
        lower_q = q.lower()
        if dom.domain == "mail" and ("oläst" in lower_q or "olästa" in lower_q or "unread" in lower_q):
            filters["status"] = "unread"

        # Operation-heuristik (MVP)
        operation = "count"
        if dom.domain == "calendar" and ("nästa" in lower_q or "next" in lower_q):
            operation = "next"
        elif dom.domain in {"notes", "files", "photos", "contacts", "mail"} and (
            "sök" in lower_q or "search" in lower_q or "find" in lower_q
        ):
            operation = "search"
        elif dom.domain == "contacts":
            operation = "list"
        elif dom.domain == "photos":
            operation = "list"
        elif dom.domain == "location":
            operation = "list"

        # Clarification
        if dom.needs_clarification or dom.domain is None:
            return self._clarification_response(
                suggestions=list(dom.suggestions) if dom.suggestions else ["calendar", "mail"],
                time_intent=parsed.time_intent,
            )

        # Policy -> timeframe (alltid satt efter policy)
        timeframe = self.time_policy.apply(dom.domain, parsed)

        return {
            "domain": dom.domain,
            "operation": operation,
            "time_intent": _safe_time_intent(parsed.time_intent.category, parsed.time_intent.payload),
            "timeframe": timeframe,
            "filters": filters or None,
            "needs_clarification": False,
            "suggestions": [],
        }

    def _clarification_response(self, *, suggestions, time_intent) -> Dict[str, object]:
        return {
            "domain": "system",
            "operation": "needs_clarification",
            "time_intent": _safe_time_intent(time_intent.category, time_intent.payload),
            "timeframe": None,
            "filters": {"suggested_domains": list(suggestions)},
            "needs_clarification": True,
            "suggestions": list(suggestions),
        }
