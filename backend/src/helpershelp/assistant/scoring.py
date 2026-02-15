"""Backward compatibility shim - imports from domain.rules.scoring"""
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

