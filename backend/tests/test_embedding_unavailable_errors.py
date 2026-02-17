import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.application.llm.llm_service import QueryInterpretationService
from helpershelp.infrastructure.llm.bge_m3_adapter import EMBEDDING_BACKEND_UNAVAILABLE
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig


class _UnavailableEmbeddingService:
    def is_available(self) -> bool:
        return False

    def refresh_model_status(self) -> bool:
        return False

    def embed_text(self, text: str):  # noqa: ARG002
        return {
            "error": "Embedding backend unavailable",
            "error_code": EMBEDDING_BACKEND_UNAVAILABLE,
        }

    def embed_batch(self, texts):  # noqa: ANN001,ARG002
        return {
            "error": "Embedding backend unavailable",
            "error_code": EMBEDDING_BACKEND_UNAVAILABLE,
        }

    def similarity(self, text1: str, text2: str):  # noqa: ARG002
        return {
            "error": "Embedding backend unavailable",
            "error_code": EMBEDDING_BACKEND_UNAVAILABLE,
        }

    def similarity_batch(self, query: str, candidates):  # noqa: ANN001,ARG002
        return {
            "error": "Embedding backend unavailable",
            "error_code": EMBEDDING_BACKEND_UNAVAILABLE,
        }


def _install_unavailable_embedding_stub():
    service = _UnavailableEmbeddingService()
    query_service = QueryInterpretationService(embedding_service=service)

    import helpershelp.api.deps as deps
    import helpershelp.api.routes.llm as llm_route
    import helpershelp.api.routes.query as query_route
    import helpershelp.application.llm.llm_service as llm_service_module
    import helpershelp.infrastructure.llm.bge_m3_adapter as bge_adapter
    import helpershelp.retrieval.retrieval_coordinator as retrieval_module

    bge_adapter._embedding_service = service
    llm_service_module._query_service = query_service

    deps.embedding_service = service
    deps.query_service = query_service

    llm_route.embedding_service = service
    llm_route.query_service = query_service
    query_route.query_service = query_service

    retrieval_module._retrieval_coordinator = None


class EmbeddingUnavailableErrorTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_unavailable.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415
        from helpershelp.api.deps import reset_assistant_store  # noqa: PLC0415

        reset_assistant_store()
        _install_unavailable_embedding_stub()

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

        self.client = TestClient(app)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_llm_embed_returns_503_when_embedding_backend_unavailable(self):
        response = self.client.post("/llm/embed", json={"text": "hej"})
        self.assertEqual(response.status_code, 503)

    def test_llm_interpret_query_returns_503_when_embedding_backend_unavailable(self):
        response = self.client.post(
            "/llm/interpret-query",
            json={"query": "vad har hänt?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 503)

    def test_query_returns_503_when_embedding_backend_unavailable(self):
        response = self.client.post(
            "/query",
            json={"query": "sammanfatta", "language": "sv", "days": 7},
        )
        self.assertEqual(response.status_code, 503)

    def test_query_question_alias_returns_503_when_embedding_backend_unavailable(self):
        response = self.client.post(
            "/query",
            json={"question": "sammanfatta", "language": "sv", "days": 7},
        )
        self.assertEqual(response.status_code, 503)

    def test_analytics_query_returns_200_when_embedding_backend_unavailable(self):
        response = self.client.post(
            "/query",
            json={"query": "Vad gjorde jag igår?", "language": "sv", "days": 7},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload.get("analysis", {}).get("intent_id"), "calendar.specific_day_query")


if __name__ == "__main__":
    unittest.main()
