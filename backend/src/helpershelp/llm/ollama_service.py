"""Backward compatibility shim - imports from infrastructure.llm.ollama_adapter"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.llm.ollama_service",
    "helpershelp.infrastructure.llm.ollama_adapter",
    removal_version="2.0.0"
)

from helpershelp.infrastructure.llm.ollama_adapter import (
    OllamaTextGenerationService,
    get_ollama_text_generation_service,
)

__all__ = ["OllamaTextGenerationService", "get_ollama_text_generation_service"]
