"""Backward compatibility shim - imports from application.assistant.sync"""
from helpershelp._deprecation import deprecated_module
import importlib

deprecated_module(
    "helpershelp.assistant.sync",
    "helpershelp.application.assistant.sync",
    removal_version="2.0.0",
)


# Provide a thin backwards-compatible `SyncController` without importing the
# full application.sync module at import time (avoids cascading deprecation
# warnings during test collection).
class SyncController:
    def __init__(self, store, config=None):
        sync_mod = importlib.import_module("helpershelp.application.assistant.sync")
        SyncConfig = getattr(sync_mod, "SyncConfig")
        start_sync_loop = getattr(sync_mod, "start_sync_loop")
        self.store = store
        self.config = config or SyncConfig()
        self._thread = start_sync_loop(store)

    def is_running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()


__all__ = ["SyncController"]
