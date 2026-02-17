import logging
import math
from typing import Dict, Optional, List

from helpershelp.infrastructure.llm.bge_m3_adapter import (
    EMBEDDING_BACKEND_UNAVAILABLE,
    EmbeddingBackendUnavailableError,
    EmbeddingService,
    get_embedding_service,
)

logger = logging.getLogger(__name__)


class QueryInterpretationService:
    """
    Similarity-based query classification (no XLM-R).

    Uses BGE-M3 embeddings and system-owned labels. The model only produces
    similarity scores; thresholds + final labels are system decisions.
    """

    # Intent labels (predefined)
    INTENT_LABELS = [
        "summary",
        "overview",
        "status",
        "question",
        "unknown",
    ]

    # Topic labels (predefined)
    TOPIC_LABELS = [
        "försäkring",
        "ekonomi",
        "arbete",
        "hälsa",
        "privat",
        "övrigt",
    ]

    # System thresholds (set by system, not model)
    INTENT_THRESHOLD = 0.75
    TOPIC_THRESHOLD = 0.7

    # Label prompts used for similarity-based classification.
    # Keep these short + multilingual-ish to improve robustness.
    _INTENT_LABEL_TEXT = {
        "summary": "sammanfatta, summera, sammanfattning, summary, recap",
        "overview": "översikt, överblick, overview, vad har hänt, läget generellt",
        "status": "status, läget just nu, current status",
        "question": "fråga, fråga om något, question, vad är, hur, varför",
        "unknown": "okänt, vet inte, unknown, oklart",
    }

    _TOPIC_LABEL_TEXT = {
        "försäkring": "försäkring, skada, skadeärende, försäkringsbolag, claim",
        "ekonomi": "ekonomi, faktura, betalning, bank, pengar, invoice",
        "arbete": "arbete, jobb, arbetsplats, chef, möte, project",
        "hälsa": "hälsa, vård, läkare, symptom, medicin",
        "privat": "privat, familj, vänner, hem, bostad",
        "övrigt": "övrigt, annat, miscellaneous, other",
    }

    def __init__(self, embedding_service: Optional[EmbeddingService] = None):
        self.embedding_service = embedding_service or get_embedding_service()

        self._intent_labels: Optional[List[str]] = None
        self._intent_embeddings: Optional[List[List[float]]] = None
        self._topic_labels: Optional[List[str]] = None
        self._topic_embeddings: Optional[List[List[float]]] = None

    def _ready(self) -> bool:
        return bool(self.embedding_service and self.embedding_service.is_available())

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

    @staticmethod
    def _raise_embedding_error(result: Dict, context: str) -> None:
        message = result.get("error") or f"{context} failed"
        if result.get("error_code") == EMBEDDING_BACKEND_UNAVAILABLE:
            raise EmbeddingBackendUnavailableError(message)
        raise RuntimeError(message)

    @staticmethod
    def _to_confidence(score: float) -> float:
        # cosine similarity ∈ [-1, 1] → confidence ∈ [0, 1]
        conf = (score + 1.0) / 2.0
        return max(0.0, min(1.0, float(conf)))

    def _ensure_intent_cache(self) -> None:
        if self._intent_embeddings is not None:
            return
        labels = list(self.INTENT_LABELS)
        label_texts = [self._INTENT_LABEL_TEXT.get(label, label) for label in labels]

        self._intent_labels = labels
        result = self.embedding_service.embed_batch(label_texts)
        if "error" in result:
            self._raise_embedding_error(result, "Intent cache embedding")
        self._intent_embeddings = [
            row.get("embedding", [])
            for row in result.get("embeddings", [])
        ]
        if len(self._intent_embeddings) != len(labels):
            raise RuntimeError(
                "Intent cache embedding count mismatch "
                f"(expected {len(labels)}, got {len(self._intent_embeddings)})"
            )

    def _ensure_topic_cache(self) -> None:
        if self._topic_embeddings is not None:
            return
        labels = list(self.TOPIC_LABELS)
        label_texts = [self._TOPIC_LABEL_TEXT.get(label, label) for label in labels]

        self._topic_labels = labels
        result = self.embedding_service.embed_batch(label_texts)
        if "error" in result:
            self._raise_embedding_error(result, "Topic cache embedding")
        self._topic_embeddings = [
            row.get("embedding", [])
            for row in result.get("embeddings", [])
        ]
        if len(self._topic_embeddings) != len(labels):
            raise RuntimeError(
                "Topic cache embedding count mismatch "
                f"(expected {len(labels)}, got {len(self._topic_embeddings)})"
            )

    def _classify_with_similarity(
        self,
        text: str,
        labels: List[str],
        label_embeddings: List[List[float]],
        threshold: float,
        output_key: str,
        fallback_label: str,
    ) -> Dict:
        query_result = self.embedding_service.embed_text(text)
        if "error" in query_result:
            self._raise_embedding_error(query_result, "Query embedding")

        query_embedding = query_result.get("embedding", [])
        if not query_embedding:
            raise RuntimeError("Query embedding is empty")

        sims = [
            self._cosine_similarity(query_embedding, label_embedding)
            for label_embedding in label_embeddings
        ]
        if not sims:
            raise RuntimeError("No label embeddings available for classification")

        best_idx = max(range(len(sims)), key=lambda idx: sims[idx])
        best_label = labels[best_idx]
        best_score = float(sims[best_idx])
        best_conf = self._to_confidence(best_score)

        all_scores = {
            label: self._to_confidence(float(sims[i]))
            for i, label in enumerate(labels)
        }

        if best_conf < threshold:
            final_label = fallback_label
            reason = f"Confidence {best_conf:.2f} below threshold {threshold}"
        else:
            final_label = best_label
            reason = "Accepted"

        logger.info(
            "%s: %s (%.2f) → %s",
            output_key.capitalize(),
            best_label,
            best_conf,
            final_label,
        )

        return {
            "text": text,
            output_key: final_label,
            "confidence": best_conf,
            "all_scores": {k: float(v) for k, v in all_scores.items()},
            "reason": reason,
        }

    def classify_intent(self, text: str) -> Dict:
        if not text or not text.strip():
            return {
                "text": text,
                "intent": "unknown",
                "confidence": 0.0,
                "reason": "Empty text",
            }

        if not self._ready():
            return {
                "text": text,
                "error": "Embedding backend unavailable",
                "error_code": EMBEDDING_BACKEND_UNAVAILABLE,
            }

        try:
            self._ensure_intent_cache()
            return self._classify_with_similarity(
                text=text,
                labels=self._intent_labels,
                label_embeddings=self._intent_embeddings,
                threshold=self.INTENT_THRESHOLD,
                output_key="intent",
                fallback_label="unknown",
            )
        except EmbeddingBackendUnavailableError as e:
            logger.error("Intent classification backend unavailable: %s", e)
            return {
                "text": text,
                "error": str(e),
                "error_code": EMBEDDING_BACKEND_UNAVAILABLE,
            }
        except Exception as e:
            logger.error("Intent classification failed: %s", e)
            return {
                "text": text,
                "intent": "unknown",
                "confidence": 0.0,
                "error": str(e),
            }

    def classify_topic(self, text: str) -> Dict:
        if not text or not text.strip():
            return {
                "text": text,
                "topic": "övrigt",
                "confidence": 0.0,
                "reason": "Empty text",
            }

        if not self._ready():
            return {
                "text": text,
                "error": "Embedding backend unavailable",
                "error_code": EMBEDDING_BACKEND_UNAVAILABLE,
            }

        try:
            self._ensure_topic_cache()
            return self._classify_with_similarity(
                text=text,
                labels=self._topic_labels,
                label_embeddings=self._topic_embeddings,
                threshold=self.TOPIC_THRESHOLD,
                output_key="topic",
                fallback_label="övrigt",
            )
        except EmbeddingBackendUnavailableError as e:
            logger.error("Topic classification backend unavailable: %s", e)
            return {
                "text": text,
                "error": str(e),
                "error_code": EMBEDDING_BACKEND_UNAVAILABLE,
            }
        except Exception as e:
            logger.error("Topic classification failed: %s", e)
            return {
                "text": text,
                "topic": "övrigt",
                "confidence": 0.0,
                "error": str(e),
            }

    def interpret_query(self, query: str, language: str = "en") -> Dict:
        if not query or not query.strip():
            return {"error": "Empty query"}

        intent_result = self.classify_intent(query)
        if "error" in intent_result:
            return {
                "error": intent_result["error"],
                **(
                    {"error_code": intent_result["error_code"]}
                    if "error_code" in intent_result
                    else {}
                ),
            }

        topic_result = self.classify_topic(query)
        if "error" in topic_result:
            return {
                "error": topic_result["error"],
                **(
                    {"error_code": topic_result["error_code"]}
                    if "error_code" in topic_result
                    else {}
                ),
            }

        return {
            "query": query,
            "language": language,
            "intent": intent_result.get("intent"),
            "intent_confidence": intent_result.get("confidence"),
            "topic": topic_result.get("topic"),
            "topic_confidence": topic_result.get("confidence"),
            "all_scores": {
                "intents": intent_result.get("all_scores"),
                "topics": topic_result.get("all_scores"),
            },
        }


# Singleton instance
_query_service: Optional[QueryInterpretationService] = None


def get_query_service() -> QueryInterpretationService:
    """Get or create singleton service."""
    global _query_service
    if _query_service is None:
        _query_service = QueryInterpretationService()
    return _query_service
