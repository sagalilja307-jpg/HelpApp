from __future__ import annotations

from datetime import datetime
from typing import Optional, cast

from helpershelp.application.query.domain_classifier import DomainClassifier
from helpershelp.application.query.timeframe_resolver import QueryTimeframeResolver
from helpershelp.application.query.time_policy import TimePolicy, TimePolicyConfig
from helpershelp.application.intent.intent_plan import IntentPlanDTO, TimeIntentDTO, TimeframeDTO, Granularity

def _to_iso_z(dt: datetime) -> str:
    # ensure_utc ger tz-aware; här vill vi “Z”
    s = dt.isoformat()
    return s.replace("+00:00", "Z")

class IntentBuilder:
    def __init__(self, *, timezone_name: str = "Europe/Stockholm"):
        self.domain_classifier = DomainClassifier()
        self.time_resolver = QueryTimeframeResolver(timezone_name=timezone_name)
        self.time_policy = TimePolicy(TimePolicyConfig(timezone_name=timezone_name))

    def build(self, query: str) -> IntentPlanDTO:
        # 1) domain
        dom = self.domain_classifier.classify(query)

        # 2) time intent + (maybe) timeframe
        parsed = self.time_resolver.resolve(query)

        # 3) MVP operation (låst)
        operation = "count"

        # 4) clarification
        if dom.needs_clarification or dom.domain is None:
            return IntentPlanDTO(
                domain=None,
                operation=operation,
                time_intent=TimeIntentDTO(
                    category=parsed.time_intent.category,
                    payload=parsed.time_intent.payload,
                ),
                timeframe=None,
                needs_clarification=True,
                suggestions=list(dom.suggestions) if dom.suggestions else ["calendar", "mail"],
            )

        # 5) policy => alltid timeframe
        tf = self.time_policy.apply(dom.domain, parsed)

        return IntentPlanDTO(
            domain=dom.domain,
            operation=operation,
            time_intent=TimeIntentDTO(
                category=parsed.time_intent.category,
                payload=parsed.time_intent.payload,
            ),
            timeframe=TimeframeDTO(
                start=_to_iso_z(cast(datetime, tf["start"])),
                end=_to_iso_z(cast(datetime, tf["end"])),
                granularity=cast(Granularity, tf["granularity"]),
            ),
            needs_clarification=False,
            suggestions=[],
        )
