from __future__ import annotations

import hashlib
import math
import re
from typing import Dict, List

from helpershelp.application.llm.llm_service import QueryInterpretationService


class DeterministicEmbeddingService:
    """Deterministic in-memory embedding stub for tests."""

    MAX_TEXT_LENGTH = 10000
    MAX_BATCH_SIZE = 100
    EMBEDDING_DIM = 1024

    def __init__(self):
        self.ollama_host = "http://test-ollama"
        self.ollama_embed_model = "bge-m3"
        self.ollama_reachable = True
        self.model_available = True
        self.missing_models: List[str] = []
        self.active_embed_endpoint = "/api/embed"

    def refresh_model_status(self) -> bool:
        self.ollama_reachable = True
        self.model_available = True
        self.missing_models = []
        return True

    def is_available(self) -> bool:
        return True

    def get_runtime_status(self) -> Dict:
        return {
            "ollama_host": self.ollama_host,
            "embedding_model": self.ollama_embed_model,
            "ollama_reachable": self.ollama_reachable,
            "model_available": self.model_available,
            "missing_models": self.missing_models,
            "active_embed_endpoint": self.active_embed_endpoint,
        }

    @staticmethod
    def _tokenize(text: str) -> List[str]:
        return [token for token in re.split(r"\W+", (text or "").lower()) if token]

    @classmethod
    def _vector_from_text(cls, text: str) -> List[float]:
        vector = [0.0] * cls.EMBEDDING_DIM
        tokens = cls._tokenize(text)
        if not tokens:
            tokens = ["__empty__"]

        for token in tokens:
            digest = hashlib.sha256(token.encode("utf-8")).digest()
            for offset in range(0, 16, 2):
                idx = ((digest[offset] << 8) | digest[offset + 1]) % cls.EMBEDDING_DIM
                sign = 1.0 if digest[16 + (offset // 2)] % 2 == 0 else -1.0
                vector[idx] += sign

        norm = math.sqrt(sum(v * v for v in vector))
        if norm == 0.0:
            vector[0] = 1.0
            norm = 1.0
        return [v / norm for v in vector]

    @staticmethod
    def _cosine_similarity(vec_a: List[float], vec_b: List[float]) -> float:
        dot_product = sum(a * b for a, b in zip(vec_a, vec_b))
        norm_a = math.sqrt(sum(a * a for a in vec_a))
        norm_b = math.sqrt(sum(b * b for b in vec_b))
        if norm_a == 0.0 or norm_b == 0.0:
            return 0.0
        return dot_product / (norm_a * norm_b)

    def embed_text(self, text: str) -> Dict:
        if not text or not text.strip():
            return {"error": "Empty text"}
        if len(text) > self.MAX_TEXT_LENGTH:
            return {"error": f"Text exceeds max length ({self.MAX_TEXT_LENGTH})"}

        embedding = self._vector_from_text(text)
        return {
            "text": text,
            "embedding": embedding,
            "embedding_dim": len(embedding),
        }

    def embed_batch(self, texts: List[str]) -> Dict:
        if not texts:
            return {"error": "Empty text list"}
        if len(texts) > self.MAX_BATCH_SIZE:
            return {"error": f"Batch exceeds max size ({self.MAX_BATCH_SIZE})"}
        if any(not text or not str(text).strip() for text in texts):
            return {"error": "Batch contains empty text"}

        rows = []
        for text in texts:
            rows.append(
                {
                    "text": text,
                    "embedding": self._vector_from_text(text),
                }
            )
        return {
            "count": len(rows),
            "embeddings": rows,
            "embedding_dim": self.EMBEDDING_DIM,
        }

    def similarity(self, text1: str, text2: str) -> Dict:
        batch = self.embed_batch([text1, text2])
        if "error" in batch:
            return batch
        vec1 = batch["embeddings"][0]["embedding"]
        vec2 = batch["embeddings"][1]["embedding"]
        return {
            "text1": text1,
            "text2": text2,
            "similarity": float(self._cosine_similarity(vec1, vec2)),
        }

    def similarity_batch(self, query_text: str, candidate_texts: List[str]) -> Dict:
        batch = self.embed_batch([query_text] + candidate_texts)
        if "error" in batch:
            return {"query": query_text, **batch}

        vectors = [row["embedding"] for row in batch["embeddings"]]
        query_vector = vectors[0]
        ranked = []
        for text, vector in zip(candidate_texts, vectors[1:]):
            ranked.append(
                {
                    "text": text,
                    "similarity": float(self._cosine_similarity(query_vector, vector)),
                }
            )
        ranked.sort(key=lambda row: row["similarity"], reverse=True)
        return {"query": query_text, "count": len(ranked), "ranked": ranked}


def install_deterministic_embedding_stubs() -> DeterministicEmbeddingService:
    service = DeterministicEmbeddingService()

    import helpershelp.api.deps as deps
    import helpershelp.api.routes.llm as llm_route
    import helpershelp.api.routes.query as query_route
    import helpershelp.application.llm.llm_service as llm_service_module
    import helpershelp.infrastructure.llm.bge_m3_adapter as bge_adapter
    import helpershelp.retrieval.retrieval_coordinator as retrieval_module

    bge_adapter._embedding_service = service

    query_service = QueryInterpretationService(embedding_service=service)
    llm_service_module._query_service = query_service

    deps.embedding_service = service
    deps.query_service = query_service

    llm_route.embedding_service = service
    llm_route.query_service = query_service
    query_route.query_service = query_service

    retrieval_module._retrieval_coordinator = None
    return service
