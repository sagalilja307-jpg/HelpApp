"""Backward compatibility shim - imports from infrastructure.persistence.sqlite_storage"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.assistant.storage",
    "helpershelp.infrastructure.persistence.sqlite_storage",
    removal_version="2.0.0"
)

from helpershelp.infrastructure.persistence.sqlite_storage import (
    SqliteStore,
    StoreConfig,
)

__all__ = ["SqliteStore", "StoreConfig"]
