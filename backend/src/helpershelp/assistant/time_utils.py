"""Backward compatibility shim - imports from domain.value_objects.time_utils"""
from helpershelp._deprecation import deprecated_module
import importlib

OLD = "helpershelp.assistant.time_utils"
NEW = "helpershelp.domain.value_objects.time_utils"

__all__ = ["utcnow"]


def __getattr__(name: str):
    if name != "utcnow":
        raise AttributeError(name)
    # Emit deprecation warning on attribute access to ensure callers
    # using already-imported shim modules still see a warning.
    deprecated_module(OLD, NEW, removal_version="2.0.0")
    mod = importlib.import_module(NEW)
    return getattr(mod, name)

