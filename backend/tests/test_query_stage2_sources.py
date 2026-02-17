import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.testing.embedding_test_utils import install_deterministic_embedding_stubs
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig
from helpershelp.domain.value_objects.time_utils import utcnow


class QueryStage2SourcesTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_stage2_sources.db"

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

    def test_query_used_sources_contains_stage2_sources_when_relevant(self):
        client = TestClient(self.app)
        now = utcnow()

        ingest_payload = {
            "items": [
                {
                    "id": "contact:stage2-1",
                    "source": "contacts",
                    "type": "contact",
                    "title": "Stage2 Contact",
                    "body": "stage2 token kontakt",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {"has_email": True},
                },
                {
                    "id": "photo:stage2-1",
                    "source": "photos",
                    "type": "photo",
                    "title": "Stage2 Photo",
                    "body": "stage2 token bild",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {"ocr_enabled": False},
                },
                {
                    "id": "file:stage2-1",
                    "source": "files",
                    "type": "file",
                    "title": "Stage2 File",
                    "body": "stage2 token fil",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {"uti": "public.plain-text"},
                },
            ]
        }
        ingest_resp = client.post("/ingest", json=ingest_payload)
        self.assertEqual(ingest_resp.status_code, 200)

        response = client.post(
            "/query",
            json={
                "query": "stage2 token sammanfattning",
                "language": "sv",
                "days": 30,
                "sources": ["assistant_store"],
            },
        )
        self.assertEqual(response.status_code, 200)

        payload = response.json()
        used_sources = set(payload.get("used_sources") or [])

        self.assertTrue("contacts" in used_sources)
        self.assertTrue("photos" in used_sources)
        self.assertTrue("files" in used_sources)

    def test_query_data_filter_applies_to_stage2_sources(self):
        client = TestClient(self.app)
        now = utcnow()

        ingest_payload = {
            "items": [
                {
                    "id": "contact:stage2-filter",
                    "source": "contacts",
                    "type": "contact",
                    "title": "Filter Contact",
                    "body": "kontakt body",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {},
                },
                {
                    "id": "photo:stage2-filter",
                    "source": "photos",
                    "type": "photo",
                    "title": "Filter Photo",
                    "body": "bild body",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                    "status": {},
                },
            ]
        }
        ingest_resp = client.post("/ingest", json=ingest_payload)
        self.assertEqual(ingest_resp.status_code, 200)

        response = client.post(
            "/query",
            json={
                "query": "vad vet du om kontakten",
                "language": "sv",
                "days": 30,
                "sources": ["assistant_store"],
                "data_filter": {"appliesTo": ["contacts"]},
            },
        )
        self.assertEqual(response.status_code, 200)

        payload = response.json()
        evidence = payload.get("evidence_items") or []
        if evidence:
            evidence_sources = {row.get("source") for row in evidence}
            self.assertTrue(evidence_sources.issubset({"contacts"}))


if __name__ == "__main__":
    unittest.main()
