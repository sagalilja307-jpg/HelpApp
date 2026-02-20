from __future__ import annotations

from typing import cast

from helpershelp.application.intent.intent_plan import IntentPlanDTO
from helpershelp.application.query.data_intent_router import DataIntentRouter


class IntentBuilder:
    """
    Backwards-compatible shim around the canonical DataIntentRouter.

    This class intentionally contains no routing logic; it delegates to DataIntentRouter
    so there is a single intent path in the codebase.
    """

    def __init__(self, *, timezone_name: str = "Europe/Stockholm"):
        self.router = DataIntentRouter(timezone_name=timezone_name)

    def build(self, query: str) -> IntentPlanDTO:
        payload = self.router.route(query=query, language="sv")
        if bool(payload.get("needs_clarification")):
            raise ValueError("IntentBuilder cannot materialize ambiguous intents; use DataIntentRouter directly.")
        return IntentPlanDTO.model_validate(cast(dict, payload))
