import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig
from helpershelp.testing.embedding_test_utils import install_deterministic_embedding_stubs


class QueryAnalyticsDispatchTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_analytics_dispatch.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415
        from helpershelp.api.deps import get_assistant_store, reset_assistant_store  # noqa: PLC0415

        self.app = app
        reset_assistant_store()
        self._get_store = get_assistant_store
        install_deterministic_embedding_stubs()

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_specific_day_query_uses_analytics_path(self):
        store = self._get_store()
        now = datetime.now(timezone.utc)
        store.upsert_calendar_feature_events(
            [
                {
                    "id": "calendar:evt-standup",
                    "event_identifier": "evt-standup",
                    "title": "Team standup",
                    "notes": "Daily sync",
                    "location": "Office",
                    "start_at": now,
                    "end_at": now + timedelta(minutes=30),
                    "is_all_day": False,
                    "calendar_title": "Work",
                    "last_modified_at": now,
                    "snapshot_hash": "sha256:standup-v1",
                }
            ]
        )

        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={"query": "Vad gjorde jag idag?", "language": "sv", "days": 90},
        )

        self.assertEqual(resp.status_code, 200)
        payload = resp.json()

        analysis = payload.get("analysis")
        self.assertIsInstance(analysis, dict)
        self.assertEqual(analysis.get("intent_id"), "calendar.specific_day_query")
        self.assertTrue(payload.get("analysis_ready"))
        self.assertEqual(payload.get("requires_sources"), [])

        insights = analysis.get("insights") or []
        self.assertGreaterEqual(len(insights), 1)
        self.assertEqual(insights[0].get("metric"), "event_count")
        self.assertEqual(insights[0].get("value"), 1)

    def test_non_analytics_query_falls_back_to_retrieval(self):
        store = self._get_store()
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        store.upsert_items(
            [
                UnifiedItem(
                    id="note:training-1",
                    source="notes",
                    type=UnifiedItemType.note,
                    title="Träning",
                    body="Löpning 5 km",
                    created_at=now,
                    updated_at=now,
                )
            ]
        )

        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={"query": "Vad skrev jag om träning?", "language": "sv", "days": 30},
        )

        self.assertEqual(resp.status_code, 200)
        payload = resp.json()

        analysis = payload.get("analysis")
        self.assertTrue(analysis is None or analysis == {})
        self.assertIn("content", payload)
        self.assertTrue(payload.get("analysis_ready"))
        self.assertEqual(payload.get("requires_sources"), [])

    def test_least_loaded_day_is_deterministic(self):
        store = self._get_store()
        now = datetime.now(timezone.utc)

        week_start = now - timedelta(days=now.weekday())
        monday = datetime(week_start.year, week_start.month, week_start.day, 9, 0, 0, tzinfo=timezone.utc)
        tuesday = monday + timedelta(days=1)

        events = [
            {
                "id": "calendar:evt-mon-1",
                "event_identifier": "evt-mon-1",
                "title": "Monday 1",
                "notes": "",
                "location": None,
                "start_at": monday,
                "end_at": monday + timedelta(hours=1),
                "is_all_day": False,
                "calendar_title": "Work",
                "last_modified_at": monday,
                "snapshot_hash": "sha256:evt-mon-1-v1",
            },
            {
                "id": "calendar:evt-mon-2",
                "event_identifier": "evt-mon-2",
                "title": "Monday 2",
                "notes": "",
                "location": None,
                "start_at": monday + timedelta(hours=2),
                "end_at": monday + timedelta(hours=3),
                "is_all_day": False,
                "calendar_title": "Work",
                "last_modified_at": monday + timedelta(hours=2),
                "snapshot_hash": "sha256:evt-mon-2-v1",
            },
            {
                "id": "calendar:evt-tue-1",
                "event_identifier": "evt-tue-1",
                "title": "Tuesday 1",
                "notes": "",
                "location": None,
                "start_at": tuesday,
                "end_at": tuesday + timedelta(hours=1),
                "is_all_day": False,
                "calendar_title": "Work",
                "last_modified_at": tuesday,
                "snapshot_hash": "sha256:evt-tue-1-v1",
            },
        ]
        store.upsert_calendar_feature_events(events)

        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={
                "query": "Vilken dag den här veckan är minst belastad?",
                "language": "sv",
                "days": 90,
            },
        )

        self.assertEqual(resp.status_code, 200)
        payload = resp.json()

        analysis = payload.get("analysis")
        self.assertIsInstance(analysis, dict)
        self.assertEqual(analysis.get("intent_id"), "calendar.least_loaded_day")
        self.assertTrue(payload.get("analysis_ready"))

        insights = analysis.get("insights") or []
        self.assertTrue(any(row.get("metric") == "least_loaded_day" for row in insights))


if __name__ == "__main__":
    unittest.main()
