import os
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType
from helpershelp.assistant.storage import SqliteStore, StoreConfig
from helpershelp.assistant.time_utils import utcnow


class SyncGmailAuthorizedTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_sync_gmail.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415
        from helpershelp.api.deps import reset_assistant_store  # noqa: PLC0415

        self.app = app
        reset_assistant_store()

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_sync_gmail_with_valid_token_returns_counts(self):
        client = TestClient(self.app)
        now = utcnow()
        sample_item = UnifiedItem(
            source="gmail",
            type=UnifiedItemType.email,
            title="Hej från Gmail",
            body="Innehåll",
            created_at=now,
            updated_at=now,
            due_at=now + timedelta(days=1),
            status={"email": {"thread_id": "thread-1", "is_replied": False}},
        )

        with patch("helpershelp.api.routes.sync.GmailAdapter.fetch_items", return_value=[sample_item]):
            response = client.post(
                "/sync/gmail",
                json={
                    "access_token": "token-123",
                    "days": 7,
                    "max_results": 10,
                },
            )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["fetched"], 1)
        self.assertGreaterEqual(payload["inserted"] + payload["updated"], 1)


if __name__ == "__main__":
    unittest.main()
