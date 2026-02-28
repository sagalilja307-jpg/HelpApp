import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.store.sqlite_storage import SqliteStore, StoreConfig


class QueryHealthIntentTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_query_health_intent.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

        self.client = TestClient(app)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_steps_query_returns_health_activity_plan(self):
        response = self.client.post(
            "/query",
            json={"query": "Hur många steg tog jag igår?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        filters = payload.get("filters") or {}
        time_scope = payload.get("time_scope") or {}

        self.assertEqual(payload.get("domain"), "health")
        self.assertEqual(payload.get("operation"), "sum")
        self.assertEqual(filters.get("subdomain"), "activity")
        self.assertEqual(filters.get("metric"), "step_count")
        self.assertEqual(filters.get("aggregation"), "sum")
        self.assertIsNone(filters.get("workout_type"))
        self.assertEqual(time_scope.get("value"), "yesterday")

    def test_heart_rate_query_returns_wellbeing_average(self):
        response = self.client.post(
            "/query",
            json={"query": "Hur var min puls förra veckan?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        filters = payload.get("filters") or {}

        self.assertEqual(payload.get("domain"), "health")
        self.assertEqual(payload.get("operation"), "sum")
        self.assertEqual(filters.get("subdomain"), "wellbeing")
        self.assertEqual(filters.get("metric"), "heart_rate")
        self.assertEqual(filters.get("aggregation"), "average")

    def test_workout_query_sets_workout_metric_and_type(self):
        response = self.client.post(
            "/query",
            json={"query": "Tränade jag löpning igår?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        filters = payload.get("filters") or {}

        self.assertEqual(payload.get("domain"), "health")
        self.assertEqual(payload.get("operation"), "count")
        self.assertEqual(filters.get("subdomain"), "activity")
        self.assertEqual(filters.get("metric"), "workout")
        self.assertEqual(filters.get("aggregation"), "count")
        self.assertEqual(filters.get("workout_type"), "running")


if __name__ == "__main__":
    unittest.main()
