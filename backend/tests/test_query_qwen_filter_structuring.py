from __future__ import annotations

from datetime import datetime, timezone
import unittest

from helpershelp.query.data_intent_router import DataIntentRouter


class _StubDomainResult:
    def __init__(self, domain=None, operation=None, filters=None):
        self.domain = domain
        self.operation = operation
        self.filters = filters or {}


class _StubIntentStructurer:
    def __init__(self, payload: _StubDomainResult):
        self.payload = payload

    def structure_intent(self, *, query: str, language: str = "sv"):
        _ = (query, language)
        return {
            "domain": self.payload.domain,
            "operation": self.payload.operation,
            "filters": self.payload.filters,
        }


class QueryQwenFilterStructuringTests(unittest.TestCase):
    def _router_with(self, *, intent_payload: _StubDomainResult) -> DataIntentRouter:
        router = DataIntentRouter(
            timezone_name="Europe/Stockholm",
            now_provider=lambda: datetime(2026, 2, 28, 13, 0, tzinfo=timezone.utc),
        )
        router.intent_structurer = _StubIntentStructurer(intent_payload)
        return router

    def test_mail_uses_qwen_filter_values_and_drops_unknown_keys(self):
        router = self._router_with(
            intent_payload=_StubDomainResult(
                domain="mail",
                operation="list",
                filters={
                    "status": "unread",
                    "participants": ["Klarna AB"],
                    "source_account": "gmail",
                    "unknown_key": "ignored",
                },
            ),
        )

        plan = router.route("Vad har jag för mejl från klarna?", language="sv")

        self.assertEqual(plan.get("domain"), "mail")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("status"), "unread")
        self.assertEqual(filters.get("participants"), ["klarna ab"])
        self.assertEqual(filters.get("source_account"), "gmail")
        self.assertNotIn("unknown_key", filters)

    def test_invalid_llm_filter_values_fall_back_to_deterministic_filters(self):
        router = self._router_with(
            intent_payload=_StubDomainResult(
                domain="mail",
                operation="list",
                filters={
                    "status": "super_urgent",
                    "participants": "klarna",
                    "has_attachment": "yes",
                },
            ),
        )

        plan = router.route("Vad har jag för mejl från klarna?", language="sv")

        filters = plan.get("filters") or {}
        self.assertIsNone(filters.get("status"))
        self.assertEqual(filters.get("participants"), ["klarna"])
        self.assertIsNone(filters.get("has_attachment"))

    def test_health_merge_keeps_workout_type_consistent_with_metric(self):
        router = self._router_with(
            intent_payload=_StubDomainResult(
                domain="health",
                operation="sum",
                filters={
                    "metric": "step_count",
                    "aggregation": "sum",
                    "workout_type": "running",
                },
            ),
        )

        plan = router.route("Hur var min puls igår?", language="sv")

        self.assertEqual(plan.get("domain"), "health")
        filters = plan.get("filters") or {}
        self.assertEqual(filters.get("metric"), "step_count")
        self.assertEqual(filters.get("aggregation"), "sum")
        self.assertIsNone(filters.get("workout_type"))


if __name__ == "__main__":
    unittest.main()
