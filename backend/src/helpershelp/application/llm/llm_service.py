import logging
from typing import Dict, Optional, List

from sentence_transformers import util

from helpershelp.infrastructure.llm.bge_m3_adapter import EmbeddingService, get_embedding_service

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
        self._intent_embeddings = None
        self._topic_labels: Optional[List[str]] = None
        self._topic_embeddings = None

    def _ready(self) -> bool:
        return bool(self.embedding_service and self.embedding_service.model)

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
        self._intent_embeddings = self.embedding_service.model.encode(
            label_texts,
            convert_to_tensor=True,
        )

    def _ensure_topic_cache(self) -> None:
        if self._topic_embeddings is not None:
            return
        labels = list(self.TOPIC_LABELS)
        label_texts = [self._TOPIC_LABEL_TEXT.get(label, label) for label in labels]

        self._topic_labels = labels
        self._topic_embeddings = self.embedding_service.model.encode(
            label_texts,
            convert_to_tensor=True,
        )

    def _classify_with_similarity(
        self,
        text: str,
        labels: List[str],
        label_embeddings,
        threshold: float,
        output_key: str,
        fallback_label: str,
    ) -> Dict:
        query_emb = self.embedding_service.model.encode(text, convert_to_tensor=True)
        sims = util.pytorch_cos_sim(query_emb, label_embeddings)[0]

        best_idx = int(sims.argmax().item())
        best_label = labels[best_idx]
        best_score = float(sims[best_idx].item())
        best_conf = self._to_confidence(best_score)

        all_scores = {
            label: self._to_confidence(float(sims[i].item()))
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
                "intent": "unknown",
                "confidence": 0.0,
                "reason": "Embedding model not loaded",
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
                "topic": "övrigt",
                "confidence": 0.0,
                "reason": "Embedding model not loaded",
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
        topic_result = self.classify_topic(query)

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
