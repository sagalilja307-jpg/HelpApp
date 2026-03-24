from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from helpershelp.store.sqlite_storage import SqliteStore, StoreConfig


class APIRouteTestCase(unittest.TestCase):
    db_filename = "test.db"

    def setUp(self) -> None:
        super().setUp()
        self._original_env = {
            "HELPERSHELP_DB_PATH": os.environ.get("HELPERSHELP_DB_PATH"),
            "HELPERSHELP_ENABLE_SYNC_LOOP": os.environ.get("HELPERSHELP_ENABLE_SYNC_LOOP"),
        }
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / self.db_filename

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"

        from helpershelp.api.app import app  # noqa: PLC0415

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

        self.app = app
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.client.close()
        self.tmpdir.cleanup()

        for key, value in self._original_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        super().tearDown()
