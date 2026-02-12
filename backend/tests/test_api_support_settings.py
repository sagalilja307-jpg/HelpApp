import json
import os
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType
from helpershelp.assistant.time_utils import utcnow


class APISupportSettingsTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "support_api.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415
        from helpershelp.api.deps import get_assistant_store, reset_assistant_store  # noqa: PLC0415

        self.app = app
        reset_assistant_store()
        self._get_store = get_assistant_store
        self.client = TestClient(self.app)

    def tearDown(self):
        self.tmpdir.cleanup()

    def _ingest_items(self, items):
        payload = {"items": []}
        for item in items:
            if hasattr(item, "model_dump"):
                payload["items"].append(item.model_dump(mode="json"))
            else:
                payload["items"].append(json.loads(item.json()))
        response = self.client.post("/ingest", json=payload)
        self.assertEqual(response.status_code, 200)

    def test_support_defaults_on_empty_store(self):
        response = self.client.get("/settings/support")
        self.assertEqual(response.status_code, 200)
        payload = response.json()

        self.assertEqual(payload["support_level"], 1)
        self.assertEqual(payload["paused"], False)
        self.assertEqual(payload["adaptation_enabled"], True)
        self.assertEqual(payload["time_critical_window_hours"], 24)
        self.assertEqual(payload["daily_caps"], {"0": 0, "1": 2, "2": 3, "3": 5})
        self.assertEqual(payload["effective_policy"]["nudge_limit_per_day"], 2)

    def test_support_level_validation(self):
        response = self.client.post("/settings/support", json={"support_level": 4})
        self.assertEqual(response.status_code, 422)

    def test_level_zero_hides_proposals_but_keeps_time_critical_visibility(self):
        now = utcnow()
        task = UnifiedItem(
            source="ios_push",
            type=UnifiedItemType.task,
            title="Critical task",
            body="",
            created_at=now,
            updated_at=now,
            due_at=now + timedelta(hours=2),
            status={"state": "open"},
        )
        self._ingest_items([task])

        update = self.client.post("/settings/support", json={"support_level": 0})
        self.assertEqual(update.status_code, 200)

        dashboard = self.client.get("/dashboard")
        self.assertEqual(dashboard.status_code, 200)
        payload = dashboard.json()

        self.assertGreaterEqual(len(payload["important_now"]), 1)
        self.assertEqual(payload["proposals"], [])

    def test_level_one_applies_daily_nudge_cap(self):
        now = utcnow()
        tasks = []
        for index in range(6):
            tasks.append(
                UnifiedItem(
                    source="ios_push",
                    type=UnifiedItemType.task,
                    title=f"Task {index}",
                    body="",
                    created_at=now,
                    updated_at=now,
                    due_at=now + timedelta(hours=4 + index),
                    status={"state": "open"},
                )
            )
        self._ingest_items(tasks)

        support_update = self.client.post("/settings/support", json={"support_level": 1})
        self.assertEqual(support_update.status_code, 200)

        dashboard = self.client.get("/dashboard")
        self.assertEqual(dashboard.status_code, 200)
        first_payload = dashboard.json()
        self.assertLessEqual(len(first_payload["proposals"]), 2)

        dashboard_again = self.client.get("/dashboard")
        self.assertEqual(dashboard_again.status_code, 200)
        second_payload = dashboard_again.json()
        self.assertLessEqual(len(second_payload["proposals"]), 2)

    def test_adaptation_can_be_paused_without_changing_support_level(self):
        now = utcnow()
        stale_email = UnifiedItem(
            source="gmail",
            type=UnifiedItemType.email,
            title="Need your answer?",
            body="Can you confirm?",
            created_at=now - timedelta(days=5),
            updated_at=now - timedelta(days=5),
            status={"email": {"direction": "inbound", "is_replied": False, "thread_id": "t1"}},
        )
        self._ingest_items([stale_email])

        self.client.post("/settings", json={"settings": {"assistant.follow_up_days": 3}})
        support_update = self.client.post(
            "/settings/support",
            json={"support_level": 3, "adaptation_enabled": False},
        )
        self.assertEqual(support_update.status_code, 200)

        dashboard = self.client.get("/dashboard")
        self.assertEqual(dashboard.status_code, 200)
        proposals = dashboard.json().get("proposals", [])
        self.assertGreaterEqual(len(proposals), 1)

        proposal_id = proposals[0]["id"]
        dismiss = self.client.post(
            f"/proposals/{proposal_id}/dismiss",
            json={"user_edits": {}},
        )
        self.assertEqual(dismiss.status_code, 200)

        settings_response = self.client.get("/settings")
        self.assertEqual(settings_response.status_code, 200)
        settings = settings_response.json()["settings"]
        self.assertEqual(settings.get("assistant.follow_up_days"), 3)
        self.assertEqual(settings.get("assistant.support.level"), 3)

    def test_learning_reset_removes_only_learning_keys(self):
        seeded = self.client.post(
            "/settings",
            json={
                "settings": {
                    "assistant.support.level": 2,
                    "assistant.follow_up_days": 6,
                    "assistant.learning.foo": {"weight": 0.8},
                }
            },
        )
        self.assertEqual(seeded.status_code, 200)

        reset = self.client.post("/settings/learning/reset")
        self.assertEqual(reset.status_code, 200)
        reset_payload = reset.json()
        self.assertGreaterEqual(reset_payload["removed_count"], 1)

        settings_response = self.client.get("/settings")
        self.assertEqual(settings_response.status_code, 200)
        settings = settings_response.json()["settings"]
        self.assertEqual(settings.get("assistant.support.level"), 2)
        self.assertNotIn("assistant.follow_up_days", settings)
        self.assertNotIn("assistant.learning.foo", settings)

    def test_learning_endpoint_exposes_events(self):
        pause = self.client.post("/settings/learning/pause", json={"paused": True})
        self.assertEqual(pause.status_code, 200)

        learning = self.client.get("/settings/learning")
        self.assertEqual(learning.status_code, 200)
        payload = learning.json()
        self.assertIn("events", payload)
        event_types = {event["event_type"] for event in payload["events"]}
        self.assertIn("adaptation_toggled", event_types)


if __name__ == "__main__":
    unittest.main()
