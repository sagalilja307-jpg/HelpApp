import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig


class LLMRoutesRemovedTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_llm_routes_removed.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415
        from helpershelp.api.deps import reset_assistant_store  # noqa: PLC0415

        reset_assistant_store()
        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

        self.client = TestClient(app)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_llm_routes_return_404(self):
        routes = [
            ("/llm/interpret-query", {"query": "hej", "language": "sv"}),
            ("/llm/embed", {"text": "hej"}),
            ("/llm/embed-batch", {"texts": ["a", "b"]}),
            ("/llm/similarity", {"text1": "a", "text2": "b"}),
            ("/llm/similarity-batch", {"query": "a", "candidates": ["b"]}),
            ("/llm/generate", {"prompt": "hej", "max_length": 20, "language": "sv"}),
            ("/llm/formulate", {"data_type": "mail", "data": {}}),
            ("/llm/formulate-items", {"items": [], "intent": "SUMMARY", "language": "sv"}),
        ]

        for path, payload in routes:
            response = self.client.post(path, json=payload)
            self.assertEqual(response.status_code, 404, path)


if __name__ == "__main__":
    unittest.main()
