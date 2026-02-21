import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, StoreConfig


class _MockResponse:
    def __init__(self, payload, status_code=200):
        self._payload = payload
        self.status_code = status_code
        self.text = str(payload)

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            from requests import HTTPError

            error = HTTPError("error")
            error.response = self
            raise error


class OAuthGmailFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_oauth.db"

        os.environ["HELPERSHELP_DB_PATH"] = str(self.db_path)
        os.environ["HELPERSHELP_ENABLE_SYNC_LOOP"] = "0"
        os.environ["HELPERSHELP_GMAIL_CLIENT_ID"] = "test-client-id"
        os.environ["HELPERSHELP_GMAIL_CLIENT_SECRET"] = "test-client-secret"

        from helpershelp.api.app import app  # noqa: PLC0415
        
        self.app = app

        store = SqliteStore(StoreConfig(db_path=self.db_path))
        store.init()

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_start_exchange_refresh(self):
        client = TestClient(self.app)

        start = client.get(
            "/oauth/gmail/start",
            params={
                "code_challenge": "a" * 43,
                "redirect_uri": "helper-oauth://oauth/gmail/callback",
            },
        )
        self.assertEqual(start.status_code, 200)

        payload = start.json()
        self.assertIn("authorization_url", payload)
        state = payload["state"]

        with patch("helpershelp.api.routes.oauth_gmail.requests.post") as mocked_post:
            mocked_post.return_value = _MockResponse(
                {
                    "access_token": "token-1",
                    "refresh_token": "refresh-1",
                    "expires_in": 3600,
                    "token_type": "Bearer",
                }
            )

            exchange = client.post(
                "/oauth/gmail/exchange",
                json={
                    "code": "auth-code",
                    "code_verifier": "verifier",
                    "state": state,
                    "redirect_uri": "helper-oauth://oauth/gmail/callback",
                },
            )

        self.assertEqual(exchange.status_code, 200)
        exchange_payload = exchange.json()
        self.assertEqual(exchange_payload["access_token"], "token-1")
        self.assertEqual(exchange_payload["refresh_token"], "refresh-1")

        with patch("helpershelp.api.routes.oauth_gmail.requests.post") as mocked_post:
            mocked_post.return_value = _MockResponse(
                {
                    "access_token": "token-2",
                    "expires_in": 1800,
                    "token_type": "Bearer",
                }
            )
            refresh = client.post(
                "/oauth/gmail/refresh",
                json={"refresh_token": "refresh-1"},
            )

        self.assertEqual(refresh.status_code, 200)
        refresh_payload = refresh.json()
        self.assertEqual(refresh_payload["access_token"], "token-2")
        self.assertEqual(refresh_payload["refresh_token"], "refresh-1")


if __name__ == "__main__":
    unittest.main()
