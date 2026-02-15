"""Backward compatibility shim - imports from domain.rules.scoring"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.assistant.scoring",
    "helpershelp.domain.rules.scoring",
    removal_version="2.0.0"
)

from helpershelp.domain.rules.scoring import (
    ScoredItem,
    score_item,
    dedupe_scored_items,
    build_dashboard_lists,
)

__all__ = [
    "ScoredItem",
    "score_item",
    "dedupe_scored_items",
    "build_dashboard_lists",
]

