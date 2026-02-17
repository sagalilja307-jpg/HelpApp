import os
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.testing.embedding_test_utils import install_deterministic_embedding_stubs
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
        install_deterministic_embedding_stubs()

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

    def test_query_accepts_question_alias(self):
        store = self._get_store()
        now = utcnow()

        event = UnifiedItem(
            source="ios_push",
            type=UnifiedItemType.event,
            title="Alias test event",
            body="",
            created_at=now,
            updated_at=now,
            start_at=now,
            end_at=now + timedelta(hours=1),
            status={"event": {"location": "Office"}},
        )
        store.upsert_items([event])

        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={"question": "Vad har jag idag?", "language": "sv", "days": 7},
        )
        self.assertEqual(resp.status_code, 200)
        payload = resp.json()
        self.assertIn("content", payload)

    def test_query_returns_400_when_query_and_question_missing(self):
        client = TestClient(self.app)
        resp = client.post(
            "/query",
            json={"language": "sv", "days": 7},
        )
        self.assertEqual(resp.status_code, 400)
        payload = resp.json()
        message = payload.get("error", {}).get("message", "")
        self.assertIn("Either 'query' or 'question' must be provided", message)

    def test_ingest_then_query_returns_note_event_and_reminder_evidence(self):
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
                    "end_at": (now + timedelta(hours=2)).isoformat(),
                    "status": {"is_all_day": False},
                },
                {
                    "id": "reminder:item-1",
                    "source": "reminders",
                    "type": "reminder",
                    "title": "Kop solskydd",
                    "body": "",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "due_at": (now + timedelta(days=1)).isoformat(),
                    "status": {"is_completed": False},
                },
                {
                    "id": "memory:item-1",
                    "source": "notes",
                    "type": "note",
                    "title": "Reseanteckning",
                    "body": "Vi har bokat hotell i Aten",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {"memory_source": "memory"},
                },
            ]
        }

        ingest_resp = client.post("/ingest", json=ingest_payload)
        self.assertEqual(ingest_resp.status_code, 200)

        resp = client.post(
            "/query",
            json={
                "query": "Sammanfatta vad vi planerat och bokat till Grekland",
                "language": "sv",
                "days": 90,
                "sources": ["assistant_store"],
            },
        )
        self.assertEqual(resp.status_code, 200)

        payload = resp.json()
        evidence = payload.get("evidence_items")
        self.assertIsInstance(evidence, list)
        self.assertGreaterEqual(len(evidence), 1)

        titles = {row.get("title") for row in evidence}
        self.assertTrue(
            bool(
                titles.intersection(
                    {"Packa for Grekland", "Kop solskydd", "Reseanteckning"}
                )
            )
        )

        sources = {row.get("source") for row in evidence if row.get("source")}
        self.assertTrue(bool(sources.intersection({"calendar", "reminders", "notes"})))

        used_sources = payload.get("used_sources")
        self.assertIsInstance(used_sources, list)
        self.assertTrue(bool(set(used_sources).intersection({"calendar", "reminders", "notes"})))

    def test_ingest_then_query_returns_stage2_source_evidence(self):
        client = TestClient(self.app)
        now = utcnow()

        ingest_payload = {
            "items": [
                {
                    "id": "contact:anna",
                    "source": "contacts",
                    "type": "contact",
                    "title": "Anna Andersson",
                    "body": "Resekoordinator\\nanna@example.com\\n+46700000000",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {"has_email": True, "has_phone": True},
                },
                {
                    "id": "photo:asset-1",
                    "source": "photos",
                    "type": "photo",
                    "title": "Bild 2026-02-12",
                    "body": "Metadata: favoritbild fran packning",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {"ocr_enabled": False, "favorite": True},
                },
                {
                    "id": "file:doc-1",
                    "source": "files",
                    "type": "file",
                    "title": "Resplan.pdf",
                    "body": "Dokument med bokningsdetaljer",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {"uti": "com.adobe.pdf", "size_bytes": 2048},
                },
            ]
        }

        ingest_resp = client.post("/ingest", json=ingest_payload)
        self.assertEqual(ingest_resp.status_code, 200)

        resp = client.post(
            "/query",
            json={
                "query": "sammanfatta kontakter bilder och filer for resan",
                "language": "sv",
                "days": 90,
                "sources": ["assistant_store"],
            },
        )
        self.assertEqual(resp.status_code, 200)

        payload = resp.json()
        evidence = payload.get("evidence_items") or []
        self.assertGreaterEqual(len(evidence), 1)

        evidence_sources = {row.get("source") for row in evidence}
        self.assertTrue(
            bool(evidence_sources.intersection({"contacts", "photos", "files"}))
        )

        evidence_types = {row.get("type") for row in evidence}
        self.assertTrue(bool(evidence_types.intersection({"contact", "photo", "file"})))

        used_sources = payload.get("used_sources")
        self.assertIsInstance(used_sources, list)
        self.assertTrue(bool(set(used_sources).intersection({"contacts", "photos", "files"})))


if __name__ == "__main__":
    unittest.main()
