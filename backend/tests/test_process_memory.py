import logging
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from helpershelp.llm.embedding_service import EmbeddingStatus
from helpershelp.store.sqlite_storage import SqliteStore, StoreConfig


class _FakeEmbeddingService:
    def __init__(
        self,
        *,
        embedding_model: str = "bge-m3",
        vectors: list[list[float]] | None = None,
        embed_error: Exception | None = None,
    ):
        self._embedding_model = embedding_model
        self._vectors = vectors or [[0.1, -0.2, 0.3]]
        self._embed_error = embed_error

    def status(self) -> EmbeddingStatus:
        return EmbeddingStatus(
            ollama_host="http://localhost:11434",
            embedding_model=self._embedding_model,
            ollama_reachable=True,
            model_available=True,
            missing_models=[],
            active_embed_endpoint="/api/embed",
        )

    def embed_texts(self, texts):
        if self._embed_error:
            raise self._embed_error
        return list(self._vectors)


class _CaptureHandler(logging.Handler):
    def __init__(self):
        super().__init__()
        self.messages: list[str] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.messages.append(record.getMessage())


class ProcessMemoryRouteTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_process_memory.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()
        self.client = TestClient(app)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_process_memory_success_returns_expected_shape(self):
        fake = _FakeEmbeddingService(vectors=[[0.01, 0.02, -0.03]])

        with patch("helpershelp.api.routes.process_memory.get_embedding_service", return_value=fake):
            response = self.client.post(
                "/process-memory",
                json={"text": "  En idé om produkten  ", "language": "sv"},
            )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload.get("cleanText"), "En idé om produkten")
        self.assertEqual(payload.get("suggestedType"), "Idea")
        self.assertTrue(payload.get("tags"))
        self.assertEqual(payload.get("embedding"), [0.01, 0.02, -0.03])

    def test_process_memory_rejects_empty_text(self):
        response = self.client.post(
            "/process-memory",
            json={"text": "   ", "language": "sv"},
        )
        self.assertEqual(response.status_code, 422)

    def test_process_memory_rejects_too_long_text(self):
        response = self.client.post(
            "/process-memory",
            json={"text": "a" * 8001, "language": "sv"},
        )
        self.assertEqual(response.status_code, 422)

    def test_process_memory_returns_503_when_embeddings_fail(self):
        fake = _FakeEmbeddingService(embed_error=RuntimeError("offline"))

        with patch("helpershelp.api.routes.process_memory.get_embedding_service", return_value=fake):
            response = self.client.post(
                "/process-memory",
                json={"text": "Spara detta minne", "language": "sv"},
            )

        self.assertEqual(response.status_code, 503)

    def test_process_memory_rejects_non_bge_config(self):
        fake = _FakeEmbeddingService()

        with patch("helpershelp.api.routes.process_memory.OLLAMA_EMBED_MODEL", "some-other-model"):
            with patch("helpershelp.api.routes.process_memory.get_embedding_service", return_value=fake):
                response = self.client.post(
                    "/process-memory",
                    json={"text": "Spara detta minne", "language": "sv"},
                )

        self.assertEqual(response.status_code, 503)

    def test_query_logs_do_not_include_raw_text(self):
        sentinel = "SECRET_QUERY_PAYLOAD_123"
        logger = logging.getLogger("helpershelp.api.routes.query")
        handler = _CaptureHandler()
        logger.addHandler(handler)
        previous_level = logger.level
        logger.setLevel(logging.INFO)

        try:
            response = self.client.post(
                "/query",
                json={"query": sentinel, "language": "sv"},
            )
            self.assertEqual(response.status_code, 200)
        finally:
            logger.removeHandler(handler)
            logger.setLevel(previous_level)

        joined = "\n".join(handler.messages)
        self.assertNotIn(sentinel, joined)

    def test_query_exception_logs_do_not_include_raw_text(self):
        sentinel = "SECRET_QUERY_EXCEPTION_789"
        logger = logging.getLogger("helpershelp.api.routes.query")
        handler = _CaptureHandler()
        logger.addHandler(handler)
        previous_level = logger.level
        logger.setLevel(logging.INFO)

        try:
            with patch("helpershelp.api.routes.query.DataIntentRouter.route", side_effect=RuntimeError(sentinel)):
                response = self.client.post(
                    "/query",
                    json={"query": "Hej", "language": "sv"},
                )
            self.assertEqual(response.status_code, 500)
        finally:
            logger.removeHandler(handler)
            logger.setLevel(previous_level)

        joined = "\n".join(handler.messages)
        self.assertNotIn(sentinel, joined)

    def test_process_memory_logs_do_not_include_raw_text(self):
        sentinel = "SECRET_MEMORY_PAYLOAD_456"
        fake = _FakeEmbeddingService()
        logger = logging.getLogger("helpershelp.api.routes.process_memory")
        handler = _CaptureHandler()
        logger.addHandler(handler)
        previous_level = logger.level
        logger.setLevel(logging.INFO)

        try:
            with patch("helpershelp.api.routes.process_memory.get_embedding_service", return_value=fake):
                response = self.client.post(
                    "/process-memory",
                    json={"text": sentinel, "language": "sv"},
                )
                self.assertEqual(response.status_code, 200)
        finally:
            logger.removeHandler(handler)
            logger.setLevel(previous_level)

        joined = "\n".join(handler.messages)
        self.assertNotIn(sentinel, joined)

    def test_unhandled_exception_logs_do_not_include_raw_text(self):
        sentinel = "SECRET_UNHANDLED_101"
        fake = _FakeEmbeddingService()
        logger = logging.getLogger("helpershelp.api.app")
        handler = _CaptureHandler()
        logger.addHandler(handler)
        previous_level = logger.level
        logger.setLevel(logging.INFO)

        try:
            from helpershelp.api.app import app  # noqa: PLC0415

            with TestClient(app, raise_server_exceptions=False) as client:
                with patch("helpershelp.api.routes.process_memory.get_embedding_service", return_value=fake):
                    with patch("helpershelp.api.routes.process_memory._clean_text", side_effect=RuntimeError(sentinel)):
                        response = client.post(
                            "/process-memory",
                            json={"text": "hej", "language": "sv"},
                        )
            self.assertEqual(response.status_code, 500)
            self.assertEqual(response.json()["error"]["message"], "Internal server error")
        finally:
            logger.removeHandler(handler)
            logger.setLevel(previous_level)

        joined = "\n".join(handler.messages)
        self.assertNotIn(sentinel, joined)


if __name__ == "__main__":
    unittest.main()
