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


class QueryRouterFilesPhotosUnderstandingTests(unittest.TestCase):
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

    def test_generic_artifact_query_returns_files_photos_clarification(self):
        router = self._router(llm_domain="calendar")

        plan = router.route("Har jag sparat boardingkortet?", language="sv")

        self.assertEqual(plan.get("domain"), "system")
        self.assertEqual(plan.get("operation"), "needs_clarification")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("_confidence"), "low")
        self.assertEqual(filters.get("_candidate_domains"), ["files", "photos"])
        self.assertIn("boardingkort", filters.get("_matched_signals", {}).get("files", []))

    def test_screenshot_query_prefers_photos_even_if_llm_suggests_files(self):
        router = self._router(llm_domain="files")

        plan = router.route("Visa min senaste skärmdump", language="sv")

        self.assertEqual(plan.get("domain"), "photos")
        filters = plan.get("filters") or {}
        self.assertIn(filters.get("_confidence"), {"high", "medium"})
        self.assertIn("skärmdump", filters.get("_matched_signals", {}).get("photos", []))

    def test_pdf_query_prefers_files_and_extracts_text_filter(self):
        router = self._router()

        plan = router.route("Hitta pdf om boardingkort", language="sv")

        self.assertEqual(plan.get("domain"), "files")
        self.assertEqual(plan.get("operation"), "list")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("text_contains"), "boardingkort")
        self.assertIn("pdf", filters.get("_matched_signals", {}).get("files", []))

    def test_explicit_mail_attachment_query_is_not_overridden_by_files(self):
        router = self._router()

        plan = router.route("Visa mejl med bilagor från Klarna", language="sv")

        self.assertEqual(plan.get("domain"), "mail")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("participants"), ["klarna"])
        self.assertTrue(filters.get("has_attachment"))


if __name__ == "__main__":
    unittest.main()
