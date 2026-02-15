"""Backward compatibility shim - imports from application.llm.llm_service"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.llm.llm_service",
    "helpershelp.application.llm.llm_service",
    removal_version="2.0.0"
)

from helpershelp.application.llm.llm_service import QueryInterpretationService

__all__ = ["QueryInterpretationService"]
