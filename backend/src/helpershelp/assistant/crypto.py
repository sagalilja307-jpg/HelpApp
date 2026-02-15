"""Backward compatibility shim - imports from infrastructure.security.crypto_utils"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.assistant.crypto",
    "helpershelp.infrastructure.security.crypto_utils",
    removal_version="2.0.0"
)

from helpershelp.infrastructure.security.crypto_utils import (
    get_fernet,
    encrypt_json,
    decrypt_json,
)

__all__ = ["get_fernet", "encrypt_json", "decrypt_json"]
