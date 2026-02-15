"""Embedding port - abstract interface for text embeddings"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import List


class EmbeddingPort(ABC):
    """Abstract interface for embedding operations"""

    @abstractmethod
    def embed_text(self, text: str) -> List[float]:
        """Generate embedding for a single text"""
        pass

    @abstractmethod
    def embed_batch(self, texts: List[str]) -> List[List[float]]:
        """Generate embeddings for multiple texts"""
        pass

    @abstractmethod
    def compute_similarity(self, embedding1: List[float], embedding2: List[float]) -> float:
        """Compute cosine similarity between two embeddings"""
        pass

    @abstractmethod
    def rank_by_similarity(
        self,
        query_embedding: List[float],
        candidate_embeddings: List[List[float]],
    ) -> List[tuple[int, float]]:
        """
        Rank candidates by similarity to query.
        Returns list of (index, score) tuples sorted by score descending.
        """
        pass
