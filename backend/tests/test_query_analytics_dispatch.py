import os
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType
from helpershelp.domain.value_objects.time_utils import utcnow
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
        now = utcnow()

        event = UnifiedItem(
            source="calendar",
            type=UnifiedItemType.event,
            title="Team standup",
            body="Daily sync",
            created_at=now,
            updated_at=now,
            start_at=now,
            end_at=now + timedelta(minutes=30),
        )
        store.upsert_items([event])

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

        insights = analysis.get("insights") or []
        self.assertGreaterEqual(len(insights), 1)
        self.assertEqual(insights[0].get("metric"), "event_count")
        self.assertEqual(insights[0].get("value"), 1)

    def test_non_analytics_query_falls_back_to_retrieval(self):
        store = self._get_store()
        now = utcnow()

        note = UnifiedItem(
            source="notes",
            type=UnifiedItemType.note,
            title="Träning",
            body="Löpning 5 km",
            created_at=now,
            updated_at=now,
        )
        store.upsert_items([note])

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

    def test_least_loaded_day_is_deterministic(self):
        store = self._get_store()
        now = utcnow()

        week_start = now - timedelta(days=now.weekday())
        monday = datetime(week_start.year, week_start.month, week_start.day, 9, 0, 0)
        tuesday = monday + timedelta(days=1)

        items = [
            UnifiedItem(
                source="calendar",
                type=UnifiedItemType.event,
                title="Monday 1",
                body="",
                created_at=monday,
                updated_at=monday,
                start_at=monday,
                end_at=monday + timedelta(hours=1),
            ),
            UnifiedItem(
                source="calendar",
                type=UnifiedItemType.event,
                title="Monday 2",
                body="",
                created_at=monday,
                updated_at=monday,
                start_at=monday + timedelta(hours=2),
                end_at=monday + timedelta(hours=3),
            ),
            UnifiedItem(
                source="calendar",
                type=UnifiedItemType.event,
                title="Tuesday 1",
                body="",
                created_at=tuesday,
                updated_at=tuesday,
                start_at=tuesday,
                end_at=tuesday + timedelta(hours=1),
            ),
        ]
        store.upsert_items(items)

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

        insights = analysis.get("insights") or []
        self.assertTrue(any(row.get("metric") == "least_loaded_day" for row in insights))


if __name__ == "__main__":
    unittest.main()
