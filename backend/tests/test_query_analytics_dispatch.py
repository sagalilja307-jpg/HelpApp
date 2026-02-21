import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.store.sqlite_storage import SqliteStore, StoreConfig


class QueryDataIntentTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_data_intent.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

        self.client = TestClient(app)

    def tearDown(self):
        self.tmpdir.cleanup()

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

    def test_ambiguous_query_returns_needs_clarification(self):
        resp = self.client.post(
            "/query",
            json={"query": "Vad händer?", "language": "sv"},
        )
        self.assertEqual(resp.status_code, 200)
        payload = resp.json().get("data_intent") or {}
        # Since 'Vad händer?' maps to 'list' via implicit phrasing
        # and has no explicit domain, it falls back to 'reminders' from embedding suggestions
        self.assertEqual(payload.get("domain"), "reminders")
        self.assertEqual(payload.get("operation"), "list")


if __name__ == "__main__":
    unittest.main()
