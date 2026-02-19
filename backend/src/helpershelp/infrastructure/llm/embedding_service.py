from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

from .bge_m3_adapter import EmbeddingService as _BgeM3EmbeddingService


@dataclass(frozen=True)
class EmbeddingStatus:
    ollama_host: str
    embedding_model: str
    ollama_reachable: bool
    model_available: bool
    missing_models: List[str]
    active_embed_endpoint: str


class EmbeddingService:
    """
    Stable public interface for embeddings in HelpersHelp.

    This is the ONLY module other code should import from:
        from helpershelp.infrastructure.llm.embedding_service import get_embedding_service

    Internally backed by Ollama + bge-m3.
    """

    def __init__(self, backend: Optional[_BgeM3EmbeddingService] = None):
        self._backend = backend or _BgeM3EmbeddingService()

    # ---- Status / health ----

    def status(self) -> EmbeddingStatus:
        raw = self._backend.get_runtime_status()
        return EmbeddingStatus(
            ollama_host=str(raw.get("ollama_host", "")),
            embedding_model=str(raw.get("embedding_model", "")),
            ollama_reachable=bool(raw.get("ollama_reachable", False)),
            model_available=bool(raw.get("model_available", False)),
            missing_models=list(raw.get("missing_models", []) or []),
            active_embed_endpoint=str(raw.get("active_embed_endpoint", "")),
        )

    def is_available(self) -> bool:
        return self._backend.is_available()

    # ---- Embeddings ----

    def embed_text(self, text: str) -> List[float]:
        return self._backend.embed_text(text)

    def embed_texts(self, texts: Sequence[str]) -> List[List[float]]:
        return self._backend.embed_texts(texts)

    # ---- Similarity helpers ----

    def similarity_batch(self, query_text: str, candidates: Sequence[str]) -> List[Tuple[str, float]]:
        """
        Returns candidates sorted by similarity, descending.
        """
        return self._backend.similarity_batch(query_text, candidates)

    @staticmethod
    def cosine_similarity(vec_a: Sequence[float], vec_b: Sequence[float]) -> float:
        return _BgeM3EmbeddingService.cosine_similarity(vec_a, vec_b)


_embedding_service: Optional[EmbeddingService] = None


def get_embedding_service() -> EmbeddingService:
    global _embedding_service
    if _embedding_service is None:
        _embedding_service = EmbeddingService()
    return _embedding_service
