from __future__ import annotations

from datetime import datetime, timezone
import unittest

from helpershelp.query.data_intent_router import DataIntentRouter


class _StubIntentStructurer:
    def __init__(self, domain=None, operation=None, filters=None):
        self._domain = domain
        self._operation = operation
        self._filters = filters or {}

    def structure_intent(self, *, query: str, language: str = "sv"):
        _ = (query, language)
        return {
            "domain": self._domain,
            "operation": self._operation,
            "filters": self._filters,
        }


class QueryRouterWorkCalendarUnderstandingTests(unittest.TestCase):
    def _router(self, *, llm_domain=None, llm_operation=None, llm_filters=None) -> DataIntentRouter:
        router = DataIntentRouter(
            timezone_name="Europe/Stockholm",
            now_provider=lambda: datetime(2026, 3, 24, 13, 0, tzinfo=timezone.utc),
        )
        router.intent_structurer = _StubIntentStructurer(
            domain=llm_domain,
            operation=llm_operation,
            filters=llm_filters,
        )
        return router

    def test_work_duration_query_prefers_calendar_sum_duration(self):
        router = self._router(llm_domain="health", llm_operation="sum")

        plan = router.route("Hur många timmar jobbar jag den här veckan?", language="sv")

        self.assertEqual(plan.get("domain"), "calendar")
        self.assertEqual(plan.get("operation"), "sum_duration")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("semantic_intent"), "work_duration")
        self.assertEqual(filters.get("exclude_all_day"), True)
        self.assertIn("jobb", filters.get("work_terms", []))

    def test_work_next_query_prefers_calendar_latest(self):
        router = self._router(llm_domain="health")

        plan = router.route("När jobbar jag nästa gång?", language="sv")

        self.assertEqual(plan.get("domain"), "calendar")
        self.assertEqual(plan.get("operation"), "latest")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("semantic_intent"), "work_next")

    def test_work_location_query_is_left_for_location_logic(self):
        router = self._router()

        plan = router.route("Hur länge var jag på jobbet igår?", language="sv")

        self.assertNotEqual(plan.get("domain"), "calendar")
        self.assertNotEqual(plan.get("filters", {}).get("semantic_intent"), "work_duration")

    def test_mixed_work_and_health_query_returns_clarification(self):
        router = self._router()

        plan = router.route("När jobbar jag nästa gång om jag tränar i veckan?", language="sv")

        self.assertEqual(plan.get("domain"), "system")
        self.assertEqual(plan.get("operation"), "needs_clarification")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("_candidate_domains"), ["calendar", "health"])


if __name__ == "__main__":
    unittest.main()
