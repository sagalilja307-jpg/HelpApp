from __future__ import annotations

from datetime import datetime, timezone
import unittest

from helpershelp.query.data_intent_router import DataIntentRouter


class _StubDomainResult:
    def __init__(self, domain=None, suggestions=None):
        self.domain = domain
        self.suggestions = suggestions or []


class _StubClassifier:
    def __init__(self, result: _StubDomainResult):
        self._result = result

    def classify(self, query: str):
        _ = query
        return self._result


class QueryRouterDomainGuardrailsTests(unittest.TestCase):
    def _router_with(self, result: _StubDomainResult) -> DataIntentRouter:
        router = DataIntentRouter(
            timezone_name="Europe/Stockholm",
            now_provider=lambda: datetime(2026, 2, 28, 13, 0, tzinfo=timezone.utc),
        )
        router.domain_classifier = _StubClassifier(result)
        return router

    def test_rejects_health_prediction_without_health_signals(self):
        router = self._router_with(_StubDomainResult(domain="health"))

        plan = router.route("Hur många dagar ska jag vara i fjällen?", language="sv")

        self.assertEqual(plan.get("domain"), "calendar")
        self.assertNotEqual(plan.get("domain"), "health")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("location"), "fjällen")

    def test_accepts_health_prediction_with_health_signals(self):
        router = self._router_with(_StubDomainResult(domain="health"))

        plan = router.route("Hur många steg tog jag igår?", language="sv")

        self.assertEqual(plan.get("domain"), "health")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("metric"), "step_count")

    def test_skips_health_suggestion_without_health_signals(self):
        router = self._router_with(_StubDomainResult(domain=None, suggestions=["health", "calendar"]))

        plan = router.route("Hur många dagar ska jag vara i fjällen?", language="sv")

        self.assertEqual(plan.get("domain"), "calendar")


if __name__ == "__main__":
    unittest.main()
