"""Backward compatibility shim - imports from infrastructure.llm.bge_m3_adapter"""
from helpershelp.infrastructure.llm.bge_m3_adapter import (
    EmbeddingService,
    get_embedding_service,
)

__all__ = ["EmbeddingService", "get_embedding_service"]
