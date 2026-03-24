from __future__ import annotations

import json
import logging
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.middleware.cors import CORSMiddleware

from helpershelp.api.app import create_app
from helpershelp.core.config import BACKEND_DIR, get_cors_allow_origins, get_default_db_path
from helpershelp.core.logging_config import JsonLogFormatter, build_logging_config


def _cors_middleware_options():
    app = create_app()
    middleware = next(item for item in app.user_middleware if item.cls is CORSMiddleware)
    return middleware.kwargs


class RuntimeConfigTests(unittest.TestCase):
    def test_default_db_path_is_backend_relative_regardless_of_cwd(self):
        expected = BACKEND_DIR / "data" / "helpershelp.db"
        original_cwd = Path.cwd()

        with tempfile.TemporaryDirectory() as tmpdir:
            os.chdir(tmpdir)
            try:
                self.assertEqual(get_default_db_path(), expected)
            finally:
                os.chdir(original_cwd)

    def test_cors_defaults_to_wildcard_in_development(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("HELPERSHELP_ENV", None)
            os.environ.pop("HELPERSHELP_CORS_ALLOW_ORIGINS", None)

            self.assertEqual(get_cors_allow_origins(), ["*"])
            self.assertEqual(_cors_middleware_options()["allow_origins"], ["*"])

    def test_cors_defaults_to_strict_in_production(self):
        with patch.dict(os.environ, {"HELPERSHELP_ENV": "production"}, clear=False):
            os.environ.pop("HELPERSHELP_CORS_ALLOW_ORIGINS", None)

            self.assertEqual(get_cors_allow_origins(), [])
            self.assertEqual(_cors_middleware_options()["allow_origins"], [])

    def test_explicit_cors_allow_origins_override_environment(self):
        with patch.dict(
            os.environ,
            {
                "HELPERSHELP_ENV": "production",
                "HELPERSHELP_CORS_ALLOW_ORIGINS": "http://localhost:3000, https://helper.local ",
            },
            clear=False,
        ):
            expected = ["http://localhost:3000", "https://helper.local"]
            self.assertEqual(get_cors_allow_origins(), expected)
            self.assertEqual(_cors_middleware_options()["allow_origins"], expected)


class LoggingConfigTests(unittest.TestCase):
    def test_json_formatter_includes_standard_and_structured_fields(self):
        logger = logging.getLogger("helpershelp.tests.logging")
        record = logger.makeRecord(
            name=logger.name,
            level=logging.INFO,
            fn=__file__,
            lno=42,
            msg="Query request route=/query lang=%s tz=%s status=%d",
            args=("sv", "Europe/Stockholm", 200),
            exc_info=None,
            extra={"route": "/query", "lang": "sv", "tz": "Europe/Stockholm", "status": 200},
        )

        payload = json.loads(JsonLogFormatter().format(record))

        self.assertEqual(payload["message"], "Query request route=/query lang=sv tz=Europe/Stockholm status=200")
        self.assertEqual(payload["logger"], "helpershelp.tests.logging")
        self.assertEqual(payload["level"], "INFO")
        self.assertEqual(payload["route"], "/query")
        self.assertEqual(payload["lang"], "sv")
        self.assertEqual(payload["tz"], "Europe/Stockholm")
        self.assertEqual(payload["status"], 200)
        self.assertIn("timestamp", payload)

    def test_build_logging_config_uses_text_formatter_when_requested(self):
        with patch.dict(
            os.environ,
            {"HELPERSHELP_LOG_FORMAT": "text", "HELPERSHELP_LOG_LEVEL": "debug"},
            clear=False,
        ):
            config = build_logging_config()

        self.assertEqual(config["handlers"]["default"]["formatter"], "text")
        self.assertEqual(config["handlers"]["default"]["level"], "DEBUG")


if __name__ == "__main__":
    unittest.main()
