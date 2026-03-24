import unittest
from tests.api_test_case import APIRouteTestCase


class QueryDataIntentTests(APIRouteTestCase):
    db_filename = "test_data_intent.db"

    def test_next_calendar_query_returns_data_intent(self):
        resp = self.client.post(
            "/query",
            json={"query": "Vad är nästa möte?", "language": "sv"},
        )
        self.assertEqual(resp.status_code, 200)
        payload = resp.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "calendar")
        self.assertEqual(payload.get("operation"), "list")

    def test_search_notes_query_returns_data_intent(self):
        resp = self.client.post(
            "/query",
            json={"query": "Sök i anteckningar efter resa", "language": "sv"},
        )
        self.assertEqual(resp.status_code, 200)
        payload = resp.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "notes")
        self.assertEqual(payload.get("operation"), "list")

    def test_ambiguous_query_returns_clarification_payload(self):
        resp = self.client.post(
            "/query",
            json={"query": "Vad händer?", "language": "sv"},
        )
        self.assertEqual(resp.status_code, 200)
        payload = resp.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "system")
        self.assertEqual(payload.get("operation"), "needs_clarification")


if __name__ == "__main__":
    unittest.main()
