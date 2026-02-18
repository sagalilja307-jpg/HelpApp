import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig


class QueryStage3LocationTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_stage3_locations.db"

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

    def test_location_query_returns_location_domain(self):
        response = self.client.post(
            "/query",
            json={"query": "Var är jag nu?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "location")
        self.assertEqual(payload.get("operation"), "list")


if __name__ == "__main__":
    unittest.main()
