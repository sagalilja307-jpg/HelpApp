from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple

from .bge_m3_adapter import EmbeddingService as _BgeM3Backend


@dataclass(frozen=True)
class EmbeddingStatus:
    ollama_host: str
    embedding_model: str
    ollama_reachable: bool
    model_available: bool
    missing_models: List[str]
    active_embed_endpoint: str


class EmbeddingService:
    """Public embedding interface used by the rest of the backend."""

    def __init__(self, backend: Optional[_BgeM3Backend] = None):
        self._backend = backend or _BgeM3Backend()

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

    def embed_text(self, text: str) -> List[float]:
        return self._backend.embed_text(text)

    def embed_texts(self, texts: Sequence[str]) -> List[List[float]]:
        return self._backend.embed_texts(texts)

    def similarity_batch(self, query_text: str, candidates: Sequence[str]) -> List[Tuple[str, float]]:
        return self._backend.similarity_batch(query_text, candidates)


_embedding_service: Optional[EmbeddingService] = None


def get_embedding_service() -> EmbeddingService:
    global _embedding_service
    if _embedding_service is None:
        _embedding_service = EmbeddingService()
    return _embedding_service
