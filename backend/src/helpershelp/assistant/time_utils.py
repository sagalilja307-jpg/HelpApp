"""Backward compatibility shim - imports from domain.value_objects.time_utils"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.assistant.time_utils",
    "helpershelp.domain.value_objects.time_utils",
    removal_version="2.0.0"
)

from helpershelp.domain.value_objects.time_utils import utcnow

__all__ = ["utcnow"]

