import logging
from typing import List, Dict, Optional, Callable
from dataclasses import dataclass
from helpershelp.retrieval.content_object import ContentObject
from helpershelp.llm.embedding_service import get_embedding_service

logger = logging.getLogger(__name__)


@dataclass
class RetrievalConfig:
    """Configuration for retrieval pipeline."""
    relevance_threshold: float = 0.5
    max_items_total: int = 12
    max_per_source: Dict[str, int] = None
    
    def __post_init__(self):
        if self.max_per_source is None:
            self.max_per_source = {
                "email": 6,
                "memory": 4,
                "signal": 2,
                "notes": 2,
                "contacts": 2,
                "photos": 2,
                "files": 2,
                "locations": 2,
                "default": 2
            }


@dataclass
class RetrievalInterpretation:
    """Parsed user query interpretation."""
    intent: str  # "summary", "search", "list", etc
    sources: List[str]  # ["email", "memory", "signal"]
    topic_hint: str  # What to search for
    time_range: Optional[Dict] = None  # {"days": 90}
    context: Optional[Dict] = None  # Extra metadata
    data_filter: Optional[Dict] = None  # {"filterType": "unread", "appliesTo": ["email"]}


class RetrievalCoordinator:
    """
    Universal retrieval pipeline.
    
    Handles:
    - Candidate fetching from multiple sources
    - Embedding & ranking with bge-m3
    - Filtering & selection
    - Source balancing
    
    Käll-agnostisk: works med mejl, minnen, signaler, dokument osv.
    """

    def __init__(self, config: RetrievalConfig = None):
        self.config = config or RetrievalConfig()
        self.embedding_service = get_embedding_service()
        self.source_fetchers: Dict[str, Callable] = {}

    def register_source(self, source_name: str, fetcher: Callable):
        """
        Register a data source.
        
        Args:
            source_name: Name of source ("email", "memory", etc)
            fetcher: Function that returns List[ContentObject]
        """
        self.source_fetchers[source_name] = fetcher
        logger.info(f"Registered source: {source_name}")

    def retrieve(
        self,
        interpretation: RetrievalInterpretation
    ) -> List[ContentObject]:
        """
        Execute full retrieval pipeline.
        
        Args:
            interpretation: Parsed user query
        
        Returns:
            Ranked, filtered list of ContentObjects
        """

        # Step 2: Fetch candidates per source
        logger.info(f"Fetching from sources: {interpretation.sources}")
        candidates = self._fetch_candidates(
            sources=interpretation.sources,
            time_range=interpretation.time_range,
            data_filter=interpretation.data_filter
        )
        logger.info(f"Fetched {len(candidates)} candidates total")

        if not candidates:
            return []

        # Step 3-5: Embed query and all candidates in one batch
        logger.info("Scoring candidates...")
        scored_items = self._score_candidates(
            candidates=candidates,
            query_text=interpretation.topic_hint
        )

        # Step 6: Filter & select
        logger.info("Filtering and selecting...")
        final_selection = self._filter_and_select(scored_items)

        logger.info(
            f"Final selection: {len(final_selection)} items "
            f"(by source: {self._count_by_source(final_selection)})"
        )

        return final_selection

    def _fetch_candidates(
        self,
        sources: List[str],
        time_range: Optional[Dict],
        data_filter: Optional[Dict] = None
    ) -> List[ContentObject]:
        """Step 2: Hämta kandidater per källa."""

        candidates = []

        for source in sources:
            if source not in self.source_fetchers:
                logger.warning(f"Source not registered: {source}")
                continue

            try:
                fetcher = self.source_fetchers[source]
                source_candidates = fetcher(
                    time_range=time_range,
                    data_filter=data_filter
                )

                if source_candidates:
                    candidates.extend(source_candidates)
                    logger.info(f"Fetched {len(source_candidates)} from {source}")

            except Exception as e:
                logger.error(f"Error fetching from {source}: {e}")
                continue

        return candidates

    def _score_candidates(
        self,
        candidates: List[ContentObject],
        query_text: str
    ) -> List[Dict]:
        """Step 5: Beräkna likhet för alla kandidater med en batch-encode."""

        normalized_query = (query_text or "").strip()
        if not normalized_query:
            return []

        candidate_rows = []
        for item in candidates:
            text = (item.body or item.subject or "").strip()
            if text:
                candidate_rows.append((item, text))

        if not candidate_rows:
            return []

        try:
            texts = [normalized_query] + [text for _, text in candidate_rows]
            embeddings = self.embedding_service.model.encode(texts, convert_to_tensor=False)

            query_embedding = embeddings[0]
            if hasattr(query_embedding, "tolist"):
                query_embedding = query_embedding.tolist()

            scored = []
            for item_embedding, (item, _) in zip(embeddings[1:], candidate_rows):
                if hasattr(item_embedding, "tolist"):
                    item_embedding = item_embedding.tolist()

                scored.append({
                    "item": item,
                    "score": self._cosine_similarity(query_embedding, item_embedding)
                })

            return scored
        except Exception as e:
            logger.error(f"Batch scoring failed, using fallback scorer: {e}")

        query_embedding = self.embedding_service.embed_text(normalized_query).get("embedding")
        if not query_embedding:
            logger.error("Fallback scoring failed to embed query; returning unscored candidates")
            return [{"item": item, "score": 0.0} for item, _ in candidate_rows]

        scored = []
        for item, text in candidate_rows:
            try:
                item_embedding = self.embedding_service.embed_text(text).get("embedding")
                if not item_embedding:
                    continue
                scored.append({
                    "item": item,
                    "score": self._cosine_similarity(query_embedding, item_embedding)
                })
            except Exception as e:
                logger.error(f"Error scoring item {item.id}: {e}")
        return scored

    def _filter_and_select(
        self,
        scored_items: List[Dict]
    ) -> List[ContentObject]:
        """Step 6: Filtrering, urval & balansering per källa."""

        # 6a: Filtrera bort irrelevanta
        relevant = [
            item for item in scored_items
            if item["score"] >= self.config.relevance_threshold
        ]
        logger.info(
            f"Relevant after threshold: {len(relevant)} "
            f"(threshold: {self.config.relevance_threshold})"
        )

        if not relevant:
            # Fallback: if nothing passes the threshold, still return best-effort items.
            # This avoids "no information" responses when the scoring distribution is low
            # (e.g., short queries, sparse candidates, or domain mismatch).
            logger.info(
                "No items above threshold %.2f; falling back to top-scored items without threshold",
                self.config.relevance_threshold,
            )
            relevant = scored_items

        # 6b: Sortera efter score (högsta först)
        relevant_sorted = sorted(
            relevant,
            key=lambda x: x["score"],
            reverse=True
        )

        # 6c: Begränsa per källa (viktigt!)
        final_selection = []

        known_sources = {source for source in self.config.max_per_source.keys() if source != "default"}
        selected_object_ids = set()

        for source in self.config.max_per_source.keys():
            if source == "default":
                continue

            # Get max for this source
            max_for_source = self.config.max_per_source[source]

            # Find items from this source
            source_items = [
                item for item in relevant_sorted
                if item["item"].source == source
            ]

            # Add top N
            selected_for_source = source_items[:max_for_source]
            final_selection.extend(selected_for_source)
            for selected in selected_for_source:
                selected_object_ids.add(id(selected["item"]))

        default_limit = self.config.max_per_source.get("default", 2)
        if default_limit > 0:
            unknown_source_buckets: Dict[str, List[Dict]] = {}
            for item in relevant_sorted:
                source = item["item"].source
                if source in known_sources:
                    continue
                if id(item["item"]) in selected_object_ids:
                    continue
                unknown_source_buckets.setdefault(source, []).append(item)

            for source_items in unknown_source_buckets.values():
                selected_for_source = source_items[:default_limit]
                final_selection.extend(selected_for_source)
                for selected in selected_for_source:
                    selected_object_ids.add(id(selected["item"]))

        # Preserve original sort order (by score)
        final_selection.sort(
            key=lambda x: x["score"],
            reverse=True
        )

        # Limit total
        final_selection = final_selection[:self.config.max_items_total]

        return [item["item"] for item in final_selection]

    @staticmethod
    def _cosine_similarity(vec_a: List[float], vec_b: List[float]) -> float:
        """Calculate cosine similarity between two vectors."""
        import math

        if not vec_a or not vec_b:
            return 0.0

        dot_product = sum(a * b for a, b in zip(vec_a, vec_b))
        norm_a = math.sqrt(sum(a * a for a in vec_a))
        norm_b = math.sqrt(sum(b * b for b in vec_b))

        if norm_a == 0 or norm_b == 0:
            return 0.0

        return dot_product / (norm_a * norm_b)

    @staticmethod
    def _count_by_source(items: List[ContentObject]) -> Dict[str, int]:
        """Count items per source."""
        counts = {}
        for item in items:
            counts[item.source] = counts.get(item.source, 0) + 1
        return counts


# Singleton instance
_retrieval_coordinator: Optional[RetrievalCoordinator] = None


def get_retrieval_coordinator(
    config: RetrievalConfig = None
) -> RetrievalCoordinator:
    """Get or create singleton coordinator."""
    global _retrieval_coordinator
    if _retrieval_coordinator is None:
        _retrieval_coordinator = RetrievalCoordinator(config)
    return _retrieval_coordinator
