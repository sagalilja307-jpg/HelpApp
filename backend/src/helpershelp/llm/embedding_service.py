"""Backward compatibility shim - imports from infrastructure.llm.bge_m3_adapter"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.llm.embedding_service",
    "helpershelp.infrastructure.llm.bge_m3_adapter",
    removal_version="2.0.0"
)

from helpershelp.infrastructure.llm.bge_m3_adapter import (
    EmbeddingService,
    get_embedding_service,
)

__all__ = ["EmbeddingService", "get_embedding_service"]
