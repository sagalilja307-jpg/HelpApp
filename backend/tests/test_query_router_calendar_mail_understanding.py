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


class QueryRouterCalendarMailUnderstandingTests(unittest.TestCase):
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

    def test_generic_today_query_returns_clarification_instead_of_calendar_fallback(self):
        router = self._router(llm_domain="mail")

        plan = router.route("Vad händer idag?", language="sv")

        self.assertEqual(plan.get("domain"), "system")
        self.assertEqual(plan.get("operation"), "needs_clarification")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("_confidence"), "low")
        self.assertEqual(filters.get("_candidate_domains"), ["calendar", "mail"])

    def test_calendar_query_uses_calendar_even_if_llm_suggests_mail(self):
        router = self._router(llm_domain="mail")

        plan = router.route("Vad har jag i kalendern idag?", language="sv")

        self.assertEqual(plan.get("domain"), "calendar")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("_confidence"), "high")
        self.assertIn("kalender", filters.get("_matched_signals", {}).get("calendar", []))

    def test_mail_query_prefers_mail_and_keeps_strict_unread_filter(self):
        router = self._router()

        plan = router.route("Visa mina olästa mejl idag", language="sv")

        self.assertEqual(plan.get("domain"), "mail")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("status"), "unread")
        self.assertIn(filters.get("_confidence"), {"high", "medium"})
        self.assertIn("mejl", filters.get("_matched_signals", {}).get("mail", []))

    def test_explicit_notes_query_is_not_overridden_by_time_signal(self):
        router = self._router()

        plan = router.route("Visa mina anteckningar idag", language="sv")

        self.assertEqual(plan.get("domain"), "notes")


if __name__ == "__main__":
    unittest.main()
