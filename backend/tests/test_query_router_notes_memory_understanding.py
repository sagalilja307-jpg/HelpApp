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


class QueryRouterNotesMemoryUnderstandingTests(unittest.TestCase):
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

    def test_generic_topic_query_returns_notes_memory_clarification(self):
        router = self._router(llm_domain="calendar")

        plan = router.route("Har jag något om resan?", language="sv")

        self.assertEqual(plan.get("domain"), "system")
        self.assertEqual(plan.get("operation"), "needs_clarification")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("_confidence"), "low")
        self.assertEqual(filters.get("_candidate_domains"), ["memory", "notes"])

    def test_what_did_i_write_query_prefers_notes_and_extracts_topic(self):
        router = self._router(llm_domain="memory")

        plan = router.route("Vad skrev jag om resan?", language="sv")

        self.assertEqual(plan.get("domain"), "notes")
        self.assertEqual(plan.get("operation"), "list")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("text_contains"), "resan")
        self.assertIn(filters.get("_confidence"), {"high", "medium"})
        self.assertIn("notes_search", filters.get("_matched_signals", {}).get("notes", []))

    def test_what_did_i_do_last_week_prefers_memory(self):
        router = self._router()

        plan = router.route("Vad gjorde jag förra veckan?", language="sv")

        self.assertEqual(plan.get("domain"), "memory")
        self.assertEqual(plan.get("operation"), "list")
        filters = plan.get("filters") or {}
        self.assertIn(filters.get("_confidence"), {"high", "medium"})
        self.assertIn("memory_reflection", filters.get("_matched_signals", {}).get("memory", []))
        time_scope = plan.get("time_scope") or {}
        self.assertEqual(time_scope.get("type"), "relative")
        self.assertIsNotNone(time_scope.get("value"))

    def test_explicit_notes_query_is_not_overridden_by_memory_terms(self):
        router = self._router()

        plan = router.route("Visa mina anteckningar om resans mönster", language="sv")

        self.assertEqual(plan.get("domain"), "notes")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("text_contains"), "resans mönster")


if __name__ == "__main__":
    unittest.main()
