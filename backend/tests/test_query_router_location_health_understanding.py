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


class QueryRouterLocationHealthUnderstandingTests(unittest.TestCase):
    def _router(self, *, llm_domain=None, llm_operation=None, llm_filters=None) -> DataIntentRouter:
        router = DataIntentRouter(
            timezone_name="Europe/Stockholm",
            now_provider=lambda: datetime(2026, 3, 20, 9, 0, tzinfo=timezone.utc),
        )
        router.intent_structurer = _StubIntentStructurer(
            domain=llm_domain,
            operation=llm_operation,
            filters=llm_filters,
        )
        return router

    def test_explicit_location_query_prefers_location(self):
        router = self._router(llm_domain="health")

        plan = router.route("Var är jag nu?", language="sv")

        self.assertEqual(plan.get("domain"), "location")
        self.assertEqual(plan.get("operation"), "list")
        filters = plan.get("filters") or {}
        self.assertIn(filters.get("_confidence"), {"high", "medium"})
        self.assertIn("var är jag", filters.get("_matched_signals", {}).get("location", []))

    def test_place_visit_query_prefers_location_exists_and_extracts_place(self):
        router = self._router()

        plan = router.route("Har jag varit på gymmet idag?", language="sv")

        self.assertEqual(plan.get("domain"), "location")
        self.assertEqual(plan.get("operation"), "exists")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("location"), "gymmet")
        self.assertIn(filters.get("_confidence"), {"high", "medium"})

    def test_health_query_prefers_health_even_with_place_phrase(self):
        router = self._router(llm_domain="location")

        plan = router.route("Tränade jag på gymmet idag?", language="sv")

        self.assertEqual(plan.get("domain"), "health")
        self.assertEqual(plan.get("operation"), "count")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("metric"), "workout")
        self.assertEqual(filters.get("aggregation"), "count")
        self.assertIn(filters.get("_confidence"), {"high", "medium"})
        self.assertIn("metric:workout", filters.get("_matched_signals", {}).get("health", []))

    def test_location_question_about_workout_returns_clarification(self):
        router = self._router()

        plan = router.route("Var tränade jag igår?", language="sv")

        self.assertEqual(plan.get("domain"), "system")
        self.assertEqual(plan.get("operation"), "needs_clarification")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("_confidence"), "low")
        self.assertEqual(filters.get("_candidate_domains"), ["location", "health"])

    def test_explicit_health_source_breaks_workout_location_tie(self):
        router = self._router()

        plan = router.route("Var tränade jag igår i hälsodatan?", language="sv")

        self.assertEqual(plan.get("domain"), "health")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("metric"), "workout")
        self.assertEqual(filters.get("_confidence"), "high")

    def test_explicit_location_source_breaks_workout_location_tie(self):
        router = self._router()

        plan = router.route("Var tränade jag igår i platshistoriken?", language="sv")

        self.assertEqual(plan.get("domain"), "location")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("_confidence"), "high")


if __name__ == "__main__":
    unittest.main()
