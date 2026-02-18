import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig
from helpershelp.domain.value_objects.time_utils import utcnow


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

    def test_query_returns_data_intent_mail_count(self):
        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={"query": "Hur många olästa mejl har jag?", "language": "sv", "days": 7},
        )
        self.assertEqual(resp.status_code, 200)

        payload = resp.json()
        self.assertEqual(set(payload.keys()), {"data_intent"})
        data_intent = payload.get("data_intent")
        self.assertIsInstance(data_intent, dict)
        self.assertEqual(data_intent.get("domain"), "mail")
        self.assertEqual(data_intent.get("operation"), "count")
        self.assertEqual((data_intent.get("filters") or {}).get("status"), "unread")

    def test_query_accepts_question_alias(self):
        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={"question": "Visa mina möten idag", "language": "sv", "days": 7},
        )
        self.assertEqual(resp.status_code, 200)
        payload = resp.json()
        data_intent = payload.get("data_intent")
        self.assertIsInstance(data_intent, dict)
        self.assertEqual(data_intent.get("domain"), "calendar")

    def test_query_returns_422_when_query_and_question_missing(self):
        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={"language": "sv", "days": 7},
        )
        self.assertEqual(resp.status_code, 400)
        payload = resp.json()
        self.assertIn("error", payload)

    def test_ingest_accepts_items_payload(self):
        client = TestClient(self.app)
        now = utcnow()

        ingest_payload = {
            "items": [
                {
                    "id": "calendar:event-1",
                    "source": "calendar",
                    "type": "event",
                    "title": "Packa for Grekland",
                    "body": "Fixa pass och biljetter",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "start_at": now.isoformat(),
                    "end_at": now.isoformat(),
                    "status": {"is_all_day": False},
                }
            ]
        }

        ingest_resp = client.post("/ingest", json=ingest_payload)
        self.assertEqual(ingest_resp.status_code, 200)

        store = self._get_store()
        items = store.list_items(limit=10)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].title, "Packa for Grekland")

    def test_ingest_rejects_legacy_features_payload(self):
        client = TestClient(self.app)
        response = client.post(
            "/ingest",
            json={"items": [], "features": {"calendar_events": [{"id": "evt-1"}]}},
        )
        self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
