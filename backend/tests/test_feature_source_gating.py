import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig
from helpershelp.testing.embedding_test_utils import install_deterministic_embedding_stubs


class FeatureSourceGatingTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_feature_source_gating.db"

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

    def _calendar_event_payload(self, *, start: datetime, end: datetime, suffix: str = "1") -> dict:
        return {
            "id": f"calendar:evt-{suffix}:{start.isoformat()}",
            "event_identifier": f"evt-{suffix}",
            "title": "Möte",
            "notes": "Sprintplanering",
            "location": "Kontor",
            "start_at": start.isoformat(),
            "end_at": end.isoformat(),
            "is_all_day": False,
            "calendar_title": "Work",
            "last_modified_at": start.isoformat(),
            "snapshot_hash": f"sha256:evt-{suffix}-v1",
        }

    def test_analytics_query_without_calendar_features_emits_requirements(self):
        client = TestClient(self.app)
        response = client.post(
            "/query",
            json={"query": "Vad gjorde jag igår?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()

        self.assertFalse(payload.get("analysis_ready"))
        self.assertEqual(payload.get("requires_sources"), ["calendar"])
        self.assertIn("calendar_data_missing", payload.get("requirement_reason_codes") or [])
        self.assertIsInstance(payload.get("required_time_window"), dict)
        self.assertEqual(
            payload.get("analysis", {}).get("intent_id"),
            "calendar.specific_day_query",
        )

    def test_analytics_query_becomes_ready_after_calendar_feature_ingest(self):
        client = TestClient(self.app)
        now = datetime.now(timezone.utc)
        start = now.replace(hour=9, minute=0, second=0, microsecond=0)
        end = start + timedelta(hours=1)

        query = f"Vad gör jag den {start.day}/{start.month}/{start.year}?"

        pre = client.post("/query", json={"query": query, "language": "sv"})
        self.assertEqual(pre.status_code, 200)
        self.assertFalse(pre.json().get("analysis_ready"))

        ingest = client.post(
            "/ingest",
            json={
                "features": {
                    "calendar_events": [
                        self._calendar_event_payload(start=start, end=end, suffix="ready")
                    ]
                }
            },
        )
        self.assertEqual(ingest.status_code, 200)

        post = client.post("/query", json={"query": query, "language": "sv"})
        self.assertEqual(post.status_code, 200)
        payload = post.json()
        self.assertTrue(payload.get("analysis_ready"))
        self.assertEqual(payload.get("requires_sources"), [])
        self.assertEqual(payload.get("requirement_reason_codes"), [])
        self.assertEqual(payload.get("analysis", {}).get("intent_id"), "calendar.specific_day_query")

        insights = payload.get("analysis", {}).get("insights") or []
        self.assertTrue(any(row.get("metric") == "event_count" for row in insights))

    def test_feature_status_endpoint_reports_calendar_status(self):
        client = TestClient(self.app)
        now = datetime.now(timezone.utc)
        start = now.replace(hour=10, minute=0, second=0, microsecond=0)
        end = start + timedelta(hours=2)

        client.post(
            "/ingest",
            json={
                "features": {
                    "calendar_events": [
                        self._calendar_event_payload(start=start, end=end, suffix="status")
                    ]
                }
            },
        )

        response = client.get("/assistant/feature-status")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        calendar = payload.get("calendar") or {}

        self.assertTrue(calendar.get("available"))
        self.assertTrue(calendar.get("fresh"))
        self.assertGreaterEqual(calendar.get("snapshot_count", 0), 1)
        self.assertIsNotNone(calendar.get("coverage_start"))
        self.assertIsNotNone(calendar.get("coverage_end"))

    def test_stale_calendar_data_emits_stale_reason_code(self):
        client = TestClient(self.app)
        store = self._get_store()

        now = datetime.now(timezone.utc)
        start = now.replace(hour=13, minute=0, second=0, microsecond=0)
        end = start + timedelta(hours=1)
        store.upsert_calendar_feature_events(
            [
                {
                    "id": "calendar:evt-stale",
                    "event_identifier": "evt-stale",
                    "title": "Stale Event",
                    "notes": "",
                    "location": "",
                    "start_at": start,
                    "end_at": end,
                    "is_all_day": False,
                    "calendar_title": "Work",
                    "last_modified_at": start,
                    "snapshot_hash": "sha256:stale-v1",
                }
            ]
        )

        stale_time = (now - timedelta(hours=26)).isoformat()
        with store._conn() as conn:  # noqa: SLF001
            conn.execute(
                "UPDATE calendar_feature_events SET updated_at=?",
                (stale_time,),
            )

        query = f"Vad gör jag den {start.day}/{start.month}/{start.year}?"
        response = client.post("/query", json={"query": query, "language": "sv"})
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertFalse(payload.get("analysis_ready"))
        self.assertIn("calendar_data_stale", payload.get("requirement_reason_codes") or [])

    def test_coverage_gap_emits_gap_reason_code(self):
        client = TestClient(self.app)
        now = datetime.now(timezone.utc)
        start = now.replace(hour=15, minute=0, second=0, microsecond=0)
        end = start + timedelta(hours=1)

        client.post(
            "/ingest",
            json={
                "features": {
                    "calendar_events": [
                        self._calendar_event_payload(start=start, end=end, suffix="coverage")
                    ]
                }
            },
        )

        response = client.post(
            "/query",
            json={"query": "Vad gjorde jag den 1/1/2020?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertFalse(payload.get("analysis_ready"))
        self.assertIn("calendar_coverage_gap", payload.get("requirement_reason_codes") or [])

    def test_ingest_items_only_payload_is_backward_compatible(self):
        client = TestClient(self.app)
        now = datetime.now(timezone.utc).isoformat()
        payload = {
            "items": [
                {
                    "id": "note:legacy-1",
                    "source": "notes",
                    "type": "note",
                    "title": "Legacy",
                    "body": "payload",
                    "created_at": now,
                    "updated_at": now,
                    "status": {},
                }
            ]
        }
        response = client.post("/ingest", json=payload)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body.get("status"), "ok")
        self.assertEqual(body.get("inserted"), 1)


if __name__ == "__main__":
    unittest.main()

