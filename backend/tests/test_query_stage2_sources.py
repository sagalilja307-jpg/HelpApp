import unittest
from tests.api_test_case import APIRouteTestCase


class QueryStage2SourcesTests(APIRouteTestCase):
    db_filename = "test_stage2_sources.db"

    def test_query_contacts_returns_contacts_domain(self):
        response = self.client.post(
            "/query",
            json={"query": "Visa mina kontakter", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "contacts")
        self.assertEqual(payload.get("operation"), "list")

    def test_query_photos_returns_photos_domain(self):
        response = self.client.post(
            "/query",
            json={"query": "Visa mina senaste bilder", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "photos")
        self.assertEqual(payload.get("operation"), "list")


if __name__ == "__main__":
    unittest.main()
