import logging
import math
import os
from typing import Dict, List, Optional

try:
    import requests
except ImportError:  # pragma: no cover
    requests = None

logger = logging.getLogger(__name__)

EMBEDDING_BACKEND_UNAVAILABLE = "EMBEDDING_BACKEND_UNAVAILABLE"


class EmbeddingBackendUnavailableError(RuntimeError):
    """Raised when Ollama embeddings are not reachable or model is unavailable."""


class _EmbedEndpointUnavailable(RuntimeError):
    """Raised when /api/embed is unavailable and fallback should be used."""


class EmbeddingService:
    """BGE-M3 embedding + similarity service backed by Ollama HTTP APIs."""

    MAX_TEXT_LENGTH = 10000
    MAX_BATCH_SIZE = 100
    REQUEST_TIMEOUT_SECONDS = 60
    HEALTH_TIMEOUT_SECONDS = 5

    def __init__(self):
        self.ollama_host = os.getenv("OLLAMA_HOST", "http://localhost:11434")
        self.ollama_embed_model = os.getenv("OLLAMA_EMBED_MODEL", "bge-m3")
        self.model_available = False
        self.ollama_reachable = False
        self.missing_models: List[str] = [self.ollama_embed_model]
        self.active_embed_endpoint = "/api/embed"

        self.refresh_model_status()

    @staticmethod
    def _model_matches(requested_model: str, available_model: str) -> bool:
        if not requested_model or not available_model:
            return False
        if requested_model == available_model:
            return True
        prefix = requested_model.split(":")[0]
        return available_model.startswith(prefix)

    @staticmethod
    def _error(message: str, error_code: Optional[str] = None) -> Dict:
        out = {"error": message}
        if error_code:
            out["error_code"] = error_code
        return out

    def _backend_unavailable_error(self, message: str) -> Dict:
        return self._error(message, error_code=EMBEDDING_BACKEND_UNAVAILABLE)

    def refresh_model_status(self) -> bool:
        if requests is None:
            self.ollama_reachable = False
            self.model_available = False
            self.missing_models = [self.ollama_embed_model]
            logger.warning("requests library not available - embedding service disabled")
            return False

        try:
            response = requests.get(
                f"{self.ollama_host}/api/tags",
                timeout=self.HEALTH_TIMEOUT_SECONDS,
            )
            if response.status_code != 200:
                self.ollama_reachable = False
                self.model_available = False
                self.missing_models = [self.ollama_embed_model]
                logger.warning(
                    "Embedding health check failed (%s): %s",
                    response.status_code,
                    response.text,
                )
                return False

            self.ollama_reachable = True
            models = response.json().get("models", [])
            model_names = [m.get("name", "") for m in models]

            found = any(
                self._model_matches(self.ollama_embed_model, model_name)
                for model_name in model_names
            )
            self.model_available = found
            self.missing_models = [] if found else [self.ollama_embed_model]

            if found:
                logger.info(
                    "[EmbeddingService] Ollama embedding model available: %s",
                    self.ollama_embed_model,
                )
            else:
                logger.warning(
                    "[EmbeddingService] Ollama reachable but embedding model missing: %s",
                    self.ollama_embed_model,
                )
            return found
        except Exception as exc:
            self.ollama_reachable = False
            self.model_available = False
            self.missing_models = [self.ollama_embed_model]
            logger.warning("Embedding health check failed: %s", exc)
            return False

    def is_available(self) -> bool:
        if self.model_available:
            return True
        return self.refresh_model_status()

    def get_runtime_status(self) -> Dict:
        return {
            "ollama_host": self.ollama_host,
            "embedding_model": self.ollama_embed_model,
            "ollama_reachable": self.ollama_reachable,
            "model_available": self.model_available,
            "missing_models": list(self.missing_models),
            "active_embed_endpoint": self.active_embed_endpoint,
        }

    def _ensure_ready(self) -> Optional[Dict]:
        if requests is None:
            return self._backend_unavailable_error("requests library not available")

        if not self.is_available():
            return self._backend_unavailable_error(
                (
                    f"Ollama embedding model '{self.ollama_embed_model}' is unavailable "
                    f"at {self.ollama_host}"
                )
            )
        return None

    def _post_json(self, endpoint: str, payload: Dict) -> Dict:
        if requests is None:
            raise EmbeddingBackendUnavailableError("requests library not available")

        try:
            response = requests.post(
                f"{self.ollama_host}{endpoint}",
                json=payload,
                timeout=self.REQUEST_TIMEOUT_SECONDS,
            )
        except requests.exceptions.RequestException as exc:
            self.ollama_reachable = False
            self.model_available = False
            self.missing_models = [self.ollama_embed_model]
            raise EmbeddingBackendUnavailableError(
                f"Could not reach Ollama at {self.ollama_host}: {exc}"
            ) from exc

        if endpoint == "/api/embed" and response.status_code == 404:
            raise _EmbedEndpointUnavailable("/api/embed is not available")

        if response.status_code != 200:
            body_preview = response.text[:500]
            lowered_body = body_preview.lower()
            if (
                response.status_code in {404, 408, 429, 500, 502, 503, 504}
                or "model" in lowered_body
                or "not found" in lowered_body
            ):
                raise EmbeddingBackendUnavailableError(
                    f"Ollama request to {endpoint} failed ({response.status_code}): {body_preview}"
                )
            raise RuntimeError(
                f"Ollama request to {endpoint} failed ({response.status_code}): {body_preview}"
            )

        try:
            return response.json()
        except Exception as exc:
            raise RuntimeError(f"Invalid JSON response from Ollama {endpoint}: {exc}") from exc

    @staticmethod
    def _extract_embeddings_from_embed_response(data: Dict) -> List[List[float]]:
        if "embeddings" in data:
            embeddings = data.get("embeddings") or []
            if embeddings and isinstance(embeddings[0], (float, int)):
                return [list(map(float, embeddings))]
            return [list(map(float, vec)) for vec in embeddings]

        if "embedding" in data:
            embedding = data.get("embedding") or []
            return [list(map(float, embedding))]

        raise RuntimeError("Ollama embed response missing 'embedding'/'embeddings'")

    def _embed_with_primary_endpoint(self, inputs: List[str]) -> List[List[float]]:
        payload: Dict = {
            "model": self.ollama_embed_model,
            "input": inputs if len(inputs) > 1 else inputs[0],
        }
        data = self._post_json("/api/embed", payload)
        self.active_embed_endpoint = "/api/embed"
        return self._extract_embeddings_from_embed_response(data)

    def _embed_with_legacy_endpoint(self, inputs: List[str]) -> List[List[float]]:
        results: List[List[float]] = []
        for text in inputs:
            payload = {"model": self.ollama_embed_model, "prompt": text}
            data = self._post_json("/api/embeddings", payload)
            embedding = data.get("embedding")
            if not isinstance(embedding, list):
                raise RuntimeError("Legacy Ollama embedding response missing 'embedding' list")
            results.append([float(x) for x in embedding])
        self.active_embed_endpoint = "/api/embeddings"
        return results

    def _embed_texts(self, inputs: List[str]) -> List[List[float]]:
        try:
            return self._embed_with_primary_endpoint(inputs)
        except _EmbedEndpointUnavailable:
            logger.info("Falling back to legacy Ollama embeddings endpoint /api/embeddings")
            return self._embed_with_legacy_endpoint(inputs)

    @staticmethod
    def _cosine_similarity(vec_a: List[float], vec_b: List[float]) -> float:
        if not vec_a or not vec_b:
            return 0.0
        dot_product = sum(a * b for a, b in zip(vec_a, vec_b))
        norm_a = math.sqrt(sum(a * a for a in vec_a))
        norm_b = math.sqrt(sum(b * b for b in vec_b))
        if norm_a == 0.0 or norm_b == 0.0:
            return 0.0
        return dot_product / (norm_a * norm_b)

    def embed_text(self, text: str) -> Dict:
        if not text or not text.strip():
            return self._error("Empty text")
        if len(text) > self.MAX_TEXT_LENGTH:
            return self._error(f"Text exceeds max length ({self.MAX_TEXT_LENGTH})")

        ready_error = self._ensure_ready()
        if ready_error:
            return ready_error

        try:
            embedding = self._embed_texts([text])[0]
            return {
                "text": text,
                "embedding": embedding,
                "embedding_dim": len(embedding),
            }
        except EmbeddingBackendUnavailableError as exc:
            logger.error("Embedding backend unavailable: %s", exc)
            return self._backend_unavailable_error(str(exc))
        except Exception as exc:
            logger.error("Embedding failed: %s", exc)
            return self._error(str(exc))

    def embed_batch(self, texts: List[str]) -> Dict:
        if not texts:
            return self._error("Empty text list")
        if len(texts) > self.MAX_BATCH_SIZE:
            return self._error(f"Batch exceeds max size ({self.MAX_BATCH_SIZE})")
        if any(not text or not str(text).strip() for text in texts):
            return self._error("Batch contains empty text")
        if any(len(text) > self.MAX_TEXT_LENGTH for text in texts):
            return self._error(f"Text exceeds max length ({self.MAX_TEXT_LENGTH})")

        ready_error = self._ensure_ready()
        if ready_error:
            return ready_error

        try:
            embeddings = self._embed_texts(texts)
            if len(embeddings) != len(texts):
                return self._error(
                    f"Embedding count mismatch: expected {len(texts)}, got {len(embeddings)}"
                )

            results = []
            for text, embedding in zip(texts, embeddings):
                results.append({"text": text, "embedding": embedding})

            return {
                "count": len(results),
                "embeddings": results,
                "embedding_dim": len(embeddings[0]) if embeddings else 0,
            }
        except EmbeddingBackendUnavailableError as exc:
            logger.error("Batch embedding backend unavailable: %s", exc)
            return self._backend_unavailable_error(str(exc))
        except Exception as exc:
            logger.error("Batch embedding failed: %s", exc)
            return self._error(str(exc))

    def similarity(self, text1: str, text2: str) -> Dict:
        if not text1 or not text2:
            return self._error("Empty text")
        if len(text1) > self.MAX_TEXT_LENGTH or len(text2) > self.MAX_TEXT_LENGTH:
            return self._error(f"Text exceeds max length ({self.MAX_TEXT_LENGTH})")

        batch_result = self.embed_batch([text1, text2])
        if "error" in batch_result:
            return {
                "text1": text1,
                "text2": text2,
                "error": batch_result["error"],
                **(
                    {"error_code": batch_result["error_code"]}
                    if "error_code" in batch_result
                    else {}
                ),
            }

        embeddings = batch_result["embeddings"]
        score = self._cosine_similarity(embeddings[0]["embedding"], embeddings[1]["embedding"])
        return {
            "text1": text1,
            "text2": text2,
            "similarity": float(score),
            "meaning": "How semantically similar (0-1) - not importance",
        }

    def similarity_batch(self, query_text: str, candidate_texts: List[str]) -> Dict:
        if not query_text or not candidate_texts:
            return self._error("Empty query or candidates")
        if len(candidate_texts) > self.MAX_BATCH_SIZE:
            return self._error(
                f"Too many candidates ({len(candidate_texts)} > {self.MAX_BATCH_SIZE})"
            )
        if len(query_text) > self.MAX_TEXT_LENGTH:
            return self._error(f"Query exceeds max length ({self.MAX_TEXT_LENGTH})")

        all_texts = [query_text] + candidate_texts
        batch_result = self.embed_batch(all_texts)
        if "error" in batch_result:
            return {
                "query": query_text,
                "error": batch_result["error"],
                **(
                    {"error_code": batch_result["error_code"]}
                    if "error_code" in batch_result
                    else {}
                ),
            }

        embedding_rows = batch_result["embeddings"]
        query_embedding = embedding_rows[0]["embedding"]
        candidate_embeddings = [row["embedding"] for row in embedding_rows[1:]]

        ranked = []
        for text, embedding in zip(candidate_texts, candidate_embeddings):
            ranked.append(
                {
                    "text": text,
                    "similarity": float(self._cosine_similarity(query_embedding, embedding)),
                }
            )
        ranked.sort(key=lambda x: x["similarity"], reverse=True)

        return {
            "query": query_text,
            "count": len(ranked),
            "ranked": ranked,
            "note": "System applies threshold, limits, balancing next",
        }


# Singleton instance
_embedding_service: Optional[EmbeddingService] = None


def get_embedding_service() -> EmbeddingService:
    """Get or create singleton service."""
    global _embedding_service
    if _embedding_service is None:
        _embedding_service = EmbeddingService()
    return _embedding_service
