"""Backward compatibility shim - imports from application.assistant.support"""
from helpershelp.application.assistant.support import (
    SupportPolicy,
    resolve_support_policy,
    filter_proposals_by_policy,
    adaptation_allowed,
    clamp_follow_up_days,
    record_learning_event,
    reset_learning_data,
)

__all__ = [
    "SupportPolicy",
    "resolve_support_policy",
    "filter_proposals_by_policy",
    "adaptation_allowed",
    "clamp_follow_up_days",
    "record_learning_event",
    "reset_learning_data",
]
