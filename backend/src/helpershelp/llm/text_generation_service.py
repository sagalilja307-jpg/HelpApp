"""Backward compatibility shim - imports from application.llm.text_generation_service"""
from helpershelp.application.llm.text_generation_service import (
    TextGenerationService,
    get_text_generation_service,
)

__all__ = ["TextGenerationService", "get_text_generation_service"]
