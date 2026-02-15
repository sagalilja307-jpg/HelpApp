"""Backward compatibility shim - imports from infrastructure.persistence.sqlite_storage"""
from helpershelp.infrastructure.persistence.sqlite_storage import (
    SqliteStore,
    StoreConfig,
)

__all__ = ["SqliteStore", "StoreConfig"]
