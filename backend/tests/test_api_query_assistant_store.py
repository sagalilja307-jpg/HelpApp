import os
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType
from helpershelp.assistant.storage import SqliteStore, StoreConfig
from helpershelp.assistant.time_utils import utcnow


class APIQueryAssistantStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_api.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        # Import after env is set so API store uses the temp DB.
        from helpershelp.api.app import app  # noqa: PLC0415
        from helpershelp.api.deps import get_assistant_store, reset_assistant_store  # noqa: PLC0415

        self.app = app
        reset_assistant_store()
        self._get_store = get_assistant_store

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_query_defaults_to_assistant_store_and_returns_evidence(self):
        store = self._get_store()
        now = utcnow()

        event = UnifiedItem(
            source="ios_push",
            type=UnifiedItemType.event,
            title="Team meeting",
            body="",
            created_at=now,
            updated_at=now,
            start_at=now,
            end_at=now + timedelta(hours=1),
            status={"event": {"location": "Office"}},
        )
        reminder = UnifiedItem(
            source="ios_push",
            type=UnifiedItemType.reminder,
            title="Buy milk",
            body="",
            created_at=now,
            updated_at=now,
            due_at=now + timedelta(days=1),
            status={"state": "open"},
        )

        store.upsert_items([event, reminder])

        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={"query": "Vad har jag idag?", "language": "sv", "days": 7},
        )
        self.assertEqual(resp.status_code, 200)

        payload = resp.json()
        self.assertIn("content", payload)
        self.assertIsInstance(payload.get("content"), str)

        evidence = payload.get("evidence_items")
        self.assertIsInstance(evidence, list)
        self.assertGreaterEqual(len(evidence), 1)

        sources = {row.get("source") for row in evidence}
        self.assertTrue(bool(sources.intersection({"calendar", "reminders"})))

        used_sources = payload.get("used_sources")
        self.assertIsInstance(used_sources, list)
        for src in sources:
            if src:
                self.assertIn(src, used_sources)

        time_range = payload.get("time_range")
        self.assertIsInstance(time_range, dict)
        self.assertEqual(time_range.get("days"), 7)


if __name__ == "__main__":
    unittest.main()
