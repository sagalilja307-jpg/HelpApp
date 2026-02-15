from __future__ import annotations

import base64
import json
import os
from hashlib import pbkdf2_hmac
from typing import Any, Dict, Optional

try:
    from cryptography.fernet import Fernet  # type: ignore
except Exception:  # pragma: no cover
    Fernet = None


def _derive_fernet_key_from_passphrase(passphrase: str, salt: bytes) -> bytes:
    raw = pbkdf2_hmac("sha256", passphrase.encode("utf-8"), salt, 200_000, dklen=32)
    return base64.urlsafe_b64encode(raw)


def get_fernet() -> Optional["Fernet"]:
    if Fernet is None:
        return None

    key = os.getenv("HELPERSHELP_SECRET_KEY", "").strip()
    if key:
        try:
            return Fernet(key.encode("utf-8"))
        except Exception:
            return None

    passphrase = os.getenv("HELPERSHELP_SECRET_PASSPHRASE", "").strip()
    if not passphrase:
        return None

    salt_b64 = os.getenv("HELPERSHELP_SECRET_SALT_B64", "").strip()
    salt = base64.urlsafe_b64decode(salt_b64.encode("utf-8")) if salt_b64 else b"helpershelp-default-salt"
    derived = _derive_fernet_key_from_passphrase(passphrase, salt=salt)
    return Fernet(derived)


def encrypt_json(payload: Dict[str, Any]) -> Optional[str]:
    f = get_fernet()
    if not f:
        return None
    token = f.encrypt(json.dumps(payload, ensure_ascii=False).encode("utf-8")).decode("utf-8")
    return f"v1:{token}"


def decrypt_json(token: str) -> Optional[Dict[str, Any]]:
    f = get_fernet()
    if not f:
        return None
    if not token or not isinstance(token, str):
        return None
    if not token.startswith("v1:"):
        return None
    raw = token[3:]
    try:
        data = f.decrypt(raw.encode("utf-8"))
        return json.loads(data.decode("utf-8"))
    except Exception:
        return None

