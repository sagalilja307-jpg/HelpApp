import os
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType
from helpershelp.assistant.storage import SqliteStore, StoreConfig
from helpershelp.assistant.time_utils import utcnow


class QueryWithNotesAndMailTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_notes_mail.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415
        from helpershelp.api.deps import get_assistant_store, reset_assistant_store  # noqa: PLC0415

        self.app = app
        reset_assistant_store()
        self._get_store = get_assistant_store

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_query_returns_evidence_for_notes_and_mail(self):
        store = self._get_store()
        now = utcnow()

        note_item = UnifiedItem(
            source="notes",
            type=UnifiedItemType.note,
            title="Grekland plan",
            body="Bokat hotell i Aten",
            created_at=now,
            updated_at=now,
        )
        mail_item = UnifiedItem(
            source="gmail",
            type=UnifiedItemType.email,
            title="Bokningsbekraftelse",
            body="Flyg bokat",
            created_at=now,
            updated_at=now,
            due_at=now + timedelta(days=2),
            status={"email": {"thread_id": "t123", "is_replied": False}},
        )

        store.upsert_items([note_item, mail_item])

        client = TestClient(self.app)
        response = client.post(
            "/query",
            json={
                "query": "sammanfatta grekland resa",
                "language": "sv",
                "days": 30,
                "sources": ["assistant_store"],
            },
        )
        self.assertEqual(response.status_code, 200)

        payload = response.json()
        evidence = payload.get("evidence_items") or []
        self.assertGreaterEqual(len(evidence), 1)

        sources = {row.get("source") for row in evidence}
        self.assertTrue(bool(sources.intersection({"notes", "email"})))


if __name__ == "__main__":
    unittest.main()
