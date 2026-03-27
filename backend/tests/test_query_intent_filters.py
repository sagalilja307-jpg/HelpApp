import unittest
from tests.api_test_case import APIRouteTestCase


class QueryIntentFilterTests(APIRouteTestCase):
    db_filename = "test_query_intent_filters.db"

    def test_next_week_query_keeps_next_week_value_and_bounds(self):
        response = self.client.post(
            "/query",
            json={"query": "Vad gör jag nästa vecka?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        time_scope = payload.get("time_scope") or {}

        self.assertEqual(payload.get("domain"), "calendar")
        self.assertEqual(time_scope.get("type"), "relative")
        self.assertEqual(time_scope.get("value"), "next_week")
        self.assertIsNotNone(time_scope.get("start"))
        self.assertIsNotNone(time_scope.get("end"))
        filters = payload.get("filters") or {}
        self.assertEqual(
            {
                key: filters.get(key)
                for key in (
                    "status",
                    "participants",
                    "location",
                    "text_contains",
                    "tags",
                    "priority",
                    "has_attachment",
                    "source_account",
                )
            },
            {
            "status": None,
            "participants": [],
            "location": None,
            "text_contains": None,
            "tags": [],
            "priority": None,
            "has_attachment": None,
            "source_account": None,
            },
        )
        self.assertEqual(filters.get("_confidence"), "medium")
        self.assertEqual(filters.get("_candidate_domains"), ["calendar"])

    def test_birthday_query_sets_participants_filter(self):
        response = self.client.post(
            "/query",
            json={"query": "Vilken dag fyller Alva år?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        filters = payload.get("filters") or {}

        self.assertEqual(payload.get("domain"), "calendar")
        self.assertEqual(filters.get("participants"), ["alva"])

    def test_mail_query_sets_mail_filters(self):
        response = self.client.post(
            "/query",
            json={"query": "Vad har jag för mejl från klarna?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        filters = payload.get("filters") or {}

        self.assertEqual(payload.get("domain"), "mail")
        self.assertEqual(filters.get("participants"), ["klarna"])
        self.assertEqual(filters.get("status"), None)

    def test_query_route_resolves_clarification_context_from_latest_assistant_turn(self):
        response = self.client.post(
            "/query",
            json={
                "query": "Kalender",
                "language": "sv",
                "clarificationContext": {
                    "originalQuery": "Vad ska jag göra idag?",
                    "candidateDomains": ["reminders", "calendar"],
                },
            },
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        time_scope = payload.get("time_scope") or {}

        self.assertEqual(payload.get("domain"), "calendar")
        self.assertNotEqual(payload.get("operation"), "needs_clarification")
        self.assertEqual(time_scope.get("value"), "today")


if __name__ == "__main__":
    unittest.main()
