"""Backward compatibility shim - imports from infrastructure.llm.ollama_adapter"""
from helpershelp.infrastructure.llm.ollama_adapter import (
    OllamaTextGenerationService,
    get_ollama_text_generation_service,
)

__all__ = ["OllamaTextGenerationService", "get_ollama_text_generation_service"]
