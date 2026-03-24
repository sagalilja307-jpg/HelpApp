import unittest
from tests.api_test_case import APIRouteTestCase


class QueryNotesAndMailTests(APIRouteTestCase):
    db_filename = "test_query_notes_mail.db"

    def test_query_notes_domain(self):
        response = self.client.post(
            "/query",
            json={"query": "Sök i anteckningar", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "notes")

    def test_query_mail_domain(self):
        response = self.client.post(
            "/query",
            json={"query": "Visa mina mejl", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "mail")


if __name__ == "__main__":
    unittest.main()
