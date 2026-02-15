"""Backward compatibility shim - imports from infrastructure.security.token_manager"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.assistant.tokens",
    "helpershelp.infrastructure.security.token_manager",
    removal_version="2.0.0"
)

from helpershelp.infrastructure.security.token_manager import (
    store_oauth_token,
    load_oauth_token,
    TOKENS_SETTINGS_KEY,
)

__all__ = ["store_oauth_token", "load_oauth_token", "TOKENS_SETTINGS_KEY"]
