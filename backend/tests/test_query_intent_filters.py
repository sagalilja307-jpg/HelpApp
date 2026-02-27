import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.store.sqlite_storage import SqliteStore, StoreConfig


class QueryIntentFilterTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_query_intent_filters.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

        self.client = TestClient(app)

    def tearDown(self):
        self.tmpdir.cleanup()

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
        self.assertEqual(payload.get("filters"), {
            "status": None,
            "participants": [],
            "location": None,
            "text_contains": None,
            "tags": [],
            "priority": None,
            "has_attachment": None,
            "source_account": None,
        })

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


if __name__ == "__main__":
    unittest.main()
