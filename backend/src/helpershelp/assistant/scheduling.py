"""Backward compatibility shim - imports from domain.rules.scheduling"""
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

