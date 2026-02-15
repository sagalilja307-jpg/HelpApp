from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, Optional

from helpershelp.infrastructure.security.crypto_utils import decrypt_json, encrypt_json, get_fernet
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore
from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.mail.oauth_models import OAuthToken


TOKENS_SETTINGS_KEY = "assistant.oauth_tokens"


def store_oauth_token(store: SqliteStore, provider: str, token: OAuthToken) -> Dict[str, Any]:
    """
    Persist tokens ONLY if encryption is available.
    If encryption isn't configured, this function stores nothing.
    """
    if not get_fernet():
        return {"stored": False, "reason": "encryption_not_configured"}

    current = store.get_settings().get(TOKENS_SETTINGS_KEY, {})
    if not isinstance(current, dict):
        current = {}

    expires_at = utcnow() + timedelta(seconds=int(token.expires_in or 0))
    payload = {
        "access_token": token.access_token,
        "refresh_token": token.refresh_token,
        "expires_at": expires_at.isoformat(),
        "token_type": token.token_type,
    }

    encrypted = encrypt_json(payload)
    if not encrypted:
        return {"stored": False, "reason": "encryption_failed"}

    current[provider] = encrypted
    store.upsert_settings({TOKENS_SETTINGS_KEY: current})
    return {"stored": True, "provider": provider}


def load_oauth_token(store: SqliteStore, provider: str) -> Optional[Dict[str, Any]]:
    current = store.get_settings().get(TOKENS_SETTINGS_KEY, {})
    if not isinstance(current, dict):
        return None
    token = current.get(provider)
    if not token:
        return None
    return decrypt_json(token)
