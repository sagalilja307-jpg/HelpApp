import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.store.sqlite_storage import SqliteStore, StoreConfig


class QueryNotesAndMailTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_query_notes_mail.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415
        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

        self.client = TestClient(app)

    def tearDown(self):
        self.tmpdir.cleanup()

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
