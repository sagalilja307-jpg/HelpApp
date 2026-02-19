# backend/src/helpershelp/infrastructure/llm/bge_m3_adapter.py
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

from helpershelp.config import OLLAMA_EMBED_MODEL  # single source of truth

from .ollama_adapter import OllamaClient, OllamaUnavailable

EMBEDDING_BACKEND_UNAVAILABLE = "EMBEDDING_BACKEND_UNAVAILABLE"


class EmbeddingBackendUnavailableError(RuntimeError):
    """Raised when embeddings are not reachable or model is unavailable."""


@dataclass(frozen=True)
class EmbeddingRuntimeStatus:
    ollama_host: str
    embedding_model: str
    ollama_reachable: bool
    model_available: bool
    missing_models: List[str]
    active_embed_endpoint: str


class EmbeddingService:
    """
    Ollama-backed embeddings service.

    - Primary endpoint: POST /api/embed (newer)
    - Fallback endpoint: POST /api/embeddings (legacy)
    """

    MAX_TEXT_LENGTH = 10_000
    MAX_BATCH_SIZE = 100
    REQUEST_TIMEOUT_SECONDS = 60
    HEALTH_TIMEOUT_SECONDS = 5

    def __init__(self, *, ollama: Optional[OllamaClient] = None, embed_model: Optional[str] = None):
        self.ollama = ollama or OllamaClient()

        # OllamaClient has .host (we removed OllamaConfig)
        self.ollama_host = getattr(self.ollama, "host", "").rstrip("/") or "http://localhost:11434"

        # single source of truth is helpershelp.config, but allow override for tests
        self.ollama_embed_model = (embed_model or OLLAMA_EMBED_MODEL).strip() or "bge-m3"

        self.ollama_reachable = False
        self.model_available = False
        self.missing_models: List[str] = [self.ollama_embed_model]
        self.active_embed_endpoint = "/api/embed"

        self.refresh_model_status()

    @staticmethod
    def _model_matches(requested_model: str, available_model: str) -> bool:
        if not requested_model or not available_model:
            return False
        if requested_model == available_model:
            return True
        # allow prefix match: "bge-m3" vs "bge-m3:latest"
        prefix = requested_model.split(":")[0]
        return available_model.startswith(prefix)

    def refresh_model_status(self) -> bool:
        try:
            data = self.ollama.get_tags(timeout_s=self.HEALTH_TIMEOUT_SECONDS)
            self.ollama_reachable = True

            models = data.get("models", []) or []
            names = [m.get("name", "") for m in models if isinstance(m, dict)]
            found = any(self._model_matches(self.ollama_embed_model, name) for name in names)

            self.model_available = found
            self.missing_models = [] if found else [self.ollama_embed_model]
            return found
        except OllamaUnavailable:
            self.ollama_reachable = False
            self.model_available = False
            self.missing_models = [self.ollama_embed_model]
            return False

    def is_available(self) -> bool:
        return self.model_available or self.refresh_model_status()

    def get_runtime_status(self) -> Dict[str, Any]:
        st = EmbeddingRuntimeStatus(
            ollama_host=self.ollama_host,
            embedding_model=self.ollama_embed_model,
            ollama_reachable=self.ollama_reachable,
            model_available=self.model_available,
            missing_models=list(self.missing_models),
            active_embed_endpoint=self.active_embed_endpoint,
        )
        return {
            "ollama_host": st.ollama_host,
            "embedding_model": st.embedding_model,
            "ollama_reachable": st.ollama_reachable,
            "model_available": st.model_available,
            "missing_models": st.missing_models,
            "active_embed_endpoint": st.active_embed_endpoint,
        }

    def _ensure_ready(self) -> None:
        if not self.is_available():
            raise EmbeddingBackendUnavailableError(
                f"Ollama embedding model '{self.ollama_embed_model}' is unavailable at {self.ollama_host}"
            )

    def _validate_texts(self, texts: Sequence[str]) -> None:
        if not texts:
            raise ValueError("Empty text list")
        if len(texts) > self.MAX_BATCH_SIZE:
            raise ValueError(f"Batch exceeds max size ({self.MAX_BATCH_SIZE})")
        for t in texts:
            if not t or not str(t).strip():
                raise ValueError("Batch contains empty text")
            if len(t) > self.MAX_TEXT_LENGTH:
                raise ValueError(f"Text exceeds max length ({self.MAX_TEXT_LENGTH})")

    def _extract_vectors(self, data: Dict[str, Any]) -> List[List[float]]:
        # /api/embed returns {"embeddings":[[...]]} for batch
        if "embeddings" in data:
            embs = data.get("embeddings") or []
            if embs and isinstance(embs[0], (int, float)):
                return [list(map(float, embs))]
            return [list(map(float, vec)) for vec in embs]

        # legacy may return {"embedding":[...]}
        if "embedding" in data:
            emb = data.get("embedding") or []
            return [list(map(float, emb))]

        raise RuntimeError("Ollama embed response missing 'embedding'/'embeddings'")

    def _embed_api_embed(self, texts: Sequence[str]) -> List[List[float]]:
        payload: Dict[str, Any] = {
            "model": self.ollama_embed_model,
            "input": list(texts) if len(texts) > 1 else texts[0],
        }
        data = self.ollama.post_json("/api/embed", payload, timeout_s=self.REQUEST_TIMEOUT_SECONDS)
        self.active_embed_endpoint = "/api/embed"
        return self._extract_vectors(data)

    def _embed_api_embeddings_legacy(self, texts: Sequence[str]) -> List[List[float]]:
        out: List[List[float]] = []
        for t in texts:
            payload = {"model": self.ollama_embed_model, "prompt": t}
            data = self.ollama.post_json("/api/embeddings", payload, timeout_s=self.REQUEST_TIMEOUT_SECONDS)
            emb = data.get("embedding")
            if not isinstance(emb, list):
                raise RuntimeError("Legacy Ollama embedding response missing 'embedding' list")
            out.append([float(x) for x in emb])
        self.active_embed_endpoint = "/api/embeddings"
        return out

    def embed_texts(self, texts: Sequence[str]) -> List[List[float]]:
        self._validate_texts(texts)
        self._ensure_ready()

        try:
            return self._embed_api_embed(texts)
        except OllamaUnavailable as exc:
            # If /api/embed is missing (older Ollama), attempt legacy.
            msg = str(exc)
            if "404" in msg or "/api/embed" in msg:
                return self._embed_api_embeddings_legacy(texts)
            raise EmbeddingBackendUnavailableError(msg) from exc

    def embed_text(self, text: str) -> List[float]:
        return self.embed_texts([text])[0]

    @staticmethod
    def cosine_similarity(vec_a: Sequence[float], vec_b: Sequence[float]) -> float:
        if not vec_a or not vec_b:
            return 0.0
        dot = sum(a * b for a, b in zip(vec_a, vec_b))
        na = math.sqrt(sum(a * a for a in vec_a))
        nb = math.sqrt(sum(b * b for b in vec_b))
        if na == 0.0 or nb == 0.0:
            return 0.0
        return float(dot / (na * nb))

    def similarity_batch(self, query_text: str, candidates: Sequence[str]) -> List[Tuple[str, float]]:
        self._validate_texts([query_text, *candidates])
        vectors = self.embed_texts([query_text, *candidates])

        q = vectors[0]
        scored = [(cand, self.cosine_similarity(q, vec)) for cand, vec in zip(candidates, vectors[1:])]
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored


# Singleton (kept for compatibility; prefer importing via embedding_service.py facade)
_embedding_service: Optional[EmbeddingService] = None


def get_embedding_service() -> EmbeddingService:
    global _embedding_service
    if _embedding_service is None:
        _embedding_service = EmbeddingService()
    return _embedding_service
