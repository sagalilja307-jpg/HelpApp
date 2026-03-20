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


class QueryRouterRemindersContactsUnderstandingTests(unittest.TestCase):
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

    def test_generic_task_query_returns_reminder_calendar_clarification(self):
        router = self._router(llm_domain="calendar")

        plan = router.route("Vad behöver jag göra idag?", language="sv")

        self.assertEqual(plan.get("domain"), "system")
        self.assertEqual(plan.get("operation"), "needs_clarification")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("_confidence"), "low")
        self.assertEqual(filters.get("_candidate_domains"), ["reminders", "calendar"])

    def test_explicit_reminder_query_prefers_reminders_and_pending_filter(self):
        router = self._router()

        plan = router.route("Visa mina öppna uppgifter idag", language="sv")

        self.assertEqual(plan.get("domain"), "reminders")
        self.assertEqual(plan.get("operation"), "list")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("status"), "pending")
        self.assertIn(filters.get("_confidence"), {"high", "medium"})
        self.assertIn("uppgift", filters.get("_matched_signals", {}).get("reminders", []))

    def test_contact_address_lookup_prefers_contacts(self):
        router = self._router(llm_domain="mail")

        plan = router.route("Vad har jag för mejladress till Alva?", language="sv")

        self.assertEqual(plan.get("domain"), "contacts")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("participants"), ["alva"])
        self.assertEqual(plan.get("operation"), "list")
        self.assertIn("mejladress", filters.get("_matched_signals", {}).get("contacts", []))

    def test_mail_query_with_sender_is_not_overridden_by_contacts(self):
        router = self._router()

        plan = router.route("Visa mina mejl från Alva", language="sv")

        self.assertEqual(plan.get("domain"), "mail")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("participants"), ["alva"])


if __name__ == "__main__":
    unittest.main()
