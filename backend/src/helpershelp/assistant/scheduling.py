"""Backward compatibility shim - imports from domain.rules.scheduling"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.assistant.scheduling",
    "helpershelp.domain.rules.scheduling",
    removal_version="2.0.0"
)

from helpershelp.domain.rules.scheduling import (
    TimeSlot,
    list_busy_intervals,
    suggest_free_slots,
)

__all__ = [
    "TimeSlot",
    "list_busy_intervals",
    "suggest_free_slots",
]

