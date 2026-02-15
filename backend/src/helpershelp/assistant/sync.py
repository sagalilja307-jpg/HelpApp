"""Backward compatibility shim - imports from application.assistant.sync"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.assistant.sync",
    "helpershelp.application.assistant.sync",
    removal_version="2.0.0"
)

from helpershelp.application.assistant.sync import (
    SyncConfig,
    SyncController,
)

__all__ = ["SyncConfig", "SyncController"]
