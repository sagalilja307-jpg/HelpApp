"""Backward compatibility shim - imports from application.llm.text_generation_service"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.llm.text_generation_service",
    "helpershelp.application.llm.text_generation_service",
    removal_version="2.0.0"
)

from helpershelp.application.llm.text_generation_service import (
    TextGenerationService,
    get_text_generation_service,
)

__all__ = ["TextGenerationService", "get_text_generation_service"]
