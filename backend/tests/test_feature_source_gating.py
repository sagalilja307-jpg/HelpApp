import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig


class SnapshotDataIntentContractTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_snapshot_contract.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415
        from helpershelp.api.deps import reset_assistant_store  # noqa: PLC0415

        reset_assistant_store()

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

        self.client = TestClient(app)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_query_returns_data_intent_only(self):
        response = self.client.post(
            "/query",
            json={"query": "Hur många olästa mejl har jag?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertIn("data_intent", payload)
        self.assertNotIn("analysis_ready", payload)
        self.assertNotIn("requires_sources", payload)

    def test_feature_status_endpoint_is_removed(self):
        response = self.client.get("/assistant/feature-status")
        self.assertEqual(response.status_code, 404)

    def test_ingest_rejects_legacy_features_payload(self):
        payload = {"items": [], "features": {"calendar_events": [{"id": "evt-1"}]}}
        response = self.client.post("/ingest", json=payload)
        self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
