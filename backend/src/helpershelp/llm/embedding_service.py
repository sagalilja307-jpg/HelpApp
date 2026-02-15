import logging
from typing import List, Dict, Optional
import os
from pathlib import Path

from sentence_transformers import SentenceTransformer, util
import torch

from helpershelp.config import HELPERSHELP_OFFLINE, MODEL_CACHE_DIR

logger = logging.getLogger(__name__)


class EmbeddingService:
    """
    BGE-M3 embedding & similarity service.
    
    MODEL CONTRACT:
    
    ┌─────────────────────────────────────────────────────────────┐
    │ bge-m3 ONLY measures semantic similarity between texts      │
    │                                                             │
    │ What it DOES:                                               │
    │ ✓ Generate embeddings (1024-dim vectors)                    │
    │ ✓ Calculate cosine similarity (0-1 scores)                  │
    │ ✓ Rank texts by semantic likeness                           │
    │                                                             │
    │ What it NEVER does:                                         │
    │ ✗ Make decisions about importance                           │
    │ ✗ Determine what should be shown                            │
    │ ✗ Replace system logic                                      │
    │ ✗ Apply thresholds (system does this)                       │
    │ ✗ Limit results (system does this)                          │
    │ ✗ See user identity or history                              │
    │                                                             │
    │ Mental model: Advanced sorting algorithm, not intelligence  │
    │                                                             │
    │ Execution order:                                            │
    │ Qwen2.5 (classify) → bge-m3 (rank) → system (filter/select)│
    │                      → Qwen2.5 (formulate)                  │
    └─────────────────────────────────────────────────────────────┘
    """

    # Safety limits (prevent abuse)
    MAX_TEXT_LENGTH = 10000
    MAX_BATCH_SIZE = 100

    def __init__(self):
        """Initialize BGE-M3 model (local-only)."""
        self.model = None
        try:
            logger.info("[EmbeddingService] Loading BGE-M3 model (local-only)...")

            base_cache = MODEL_CACHE_DIR
            hub_snapshots = base_cache / "hub" / "models--BAAI--bge-m3" / "snapshots"
            default_local = base_cache / "models--MoritzLaurer--bge-m3-zeroshot-v2.0"

            env_path = os.getenv("BGE_M3_LOCAL_PATH")
            candidate_paths = []
            if env_path:
                candidate_paths.append(Path(env_path))

            candidate_paths.append(default_local)

            if hub_snapshots.exists():
                snapshots = sorted(hub_snapshots.glob("*"))
                if snapshots:
                    candidate_paths.append(snapshots[-1])

            model_path = next((path for path in candidate_paths if path.exists()), None)

            if not model_path:
                raise FileNotFoundError(
                    "No local BGE-M3 model found. Set BGE_M3_LOCAL_PATH or place a model in .model_cache."
                )

            logger.info(f"Loading BGE-M3 from local path: {model_path}")
            self.model = SentenceTransformer(
                str(model_path),
                trust_remote_code=True,
                local_files_only=HELPERSHELP_OFFLINE
            )

            logger.info("✅ BGE-M3 model loaded successfully")

        except Exception as e:
            logger.error(f"⚠️  Failed to load BGE-M3 model: {e}")
            self.model = None

    def embed_text(self, text: str) -> Dict:
        """
        Get embedding vector for a single text.
        
        CONTRACT:
        - Input: Any text (capped at MAX_TEXT_LENGTH)
        - Output: 1024-dimensional vector only
        - No decision-making
        - No filtering
        
        Args:
            text: Text to embed
        
        Returns:
            {
                "text": "original text",
                "embedding": [0.1, 0.2, ..., 0.5],  # 1024-dim vector
                "embedding_dim": 1024
            }
        """
        
        if not text or not text.strip():
            return {"error": "Empty text"}
        
        if len(text) > self.MAX_TEXT_LENGTH:
            return {"error": f"Text exceeds max length ({self.MAX_TEXT_LENGTH})"}
        
        if not self.model:
            return {"error": "Model not loaded"}
        
        try:
            embedding = self.model.encode(text, convert_to_tensor=False)
            
            return {
                "text": text,
                "embedding": embedding.tolist(),
                "embedding_dim": len(embedding)
            }
        except Exception as e:
            logger.error(f"Embedding failed: {e}")
            return {
                "text": text,
                "error": str(e)
            }

    def embed_batch(self, texts: List[str]) -> Dict:
        """
        Get embeddings for multiple texts.
        
        CONTRACT:
        - Input: List of texts (max MAX_BATCH_SIZE items)
        - Output: Embeddings only (no ranking, no filtering)
        - System controls batching, not model
        
        Args:
            texts: List of texts to embed
        
        Returns:
            {
                "count": 2,
                "embeddings": [
                    {"text": "...", "embedding": [...]},
                    {"text": "...", "embedding": [...]}
                ]
            }
        """
        
        if not texts or len(texts) == 0:
            return {"error": "Empty text list"}
        
        if len(texts) > self.MAX_BATCH_SIZE:
            return {"error": f"Batch exceeds max size ({self.MAX_BATCH_SIZE})"}
        
        if not self.model:
            return {"error": "Model not loaded"}
        
        try:
            embeddings = self.model.encode(texts, convert_to_tensor=False)
            
            results = []
            for text, embedding in zip(texts, embeddings):
                results.append({
                    "text": text,
                    "embedding": embedding.tolist()
                })
            
            return {
                "count": len(results),
                "embeddings": results,
                "embedding_dim": len(embeddings[0])
            }
        except Exception as e:
            logger.error(f"Batch embedding failed: {e}")
            return {"error": str(e)}

    def similarity(self, text1: str, text2: str) -> Dict:
        """
        Calculate similarity between two texts.
        
        CONTRACT:
        - Input: Two texts only (no metadata, no context)
        - Output: Cosine similarity score (0-1 only)
        - Means: "How semantically similar?" — NOT "Is this important?"
        - System decides: thresholds, importance, visibility
        
        Args:
            text1: First text
            text2: Second text
        
        Returns:
            {
                "similarity": 0.85,  # 0-1 score (cosine similarity)
                "text1": "...",
                "text2": "..."
            }
        """
        
        if not text1 or not text2:
            return {"error": "Empty text"}
        
        if len(text1) > self.MAX_TEXT_LENGTH or len(text2) > self.MAX_TEXT_LENGTH:
            return {"error": f"Text exceeds max length ({self.MAX_TEXT_LENGTH})"}
        
        if not self.model:
            return {"error": "Model not loaded"}
        
        try:
            embeddings = self.model.encode([text1, text2], convert_to_tensor=True)
            
            # Cosine similarity only - nothing else
            similarity_score = util.pytorch_cos_sim(embeddings[0], embeddings[1]).item()
            
            return {
                "text1": text1,
                "text2": text2,
                "similarity": float(similarity_score),
                "meaning": "How semantically similar (0-1) - not importance"
            }
        except Exception as e:
            logger.error(f"Similarity calculation failed: {e}")
            return {
                "text1": text1,
                "text2": text2,
                "error": str(e)
            }

    def similarity_batch(self, query_text: str, candidate_texts: List[str]) -> Dict:
        """
        Calculate similarity between one query and multiple candidates.
        
        CONTRACT:
        - Input: Query text + candidate list (from system)
        - Output: Ranked list by similarity (highest first)
        - Does NOT filter, limit, or decide
        - System applies thresholds, max limits, per-source balancing
        
        Typical usage:
        ```
        104 candidates → similarity_batch() → ranked list
        → system filters (threshold 0.6)
        → system limits (max 6 per source)
        → 12 final items to Qwen2.5
        ```
        
        Args:
            query_text: Query/topic (NOT full user question)
            candidate_texts: List of items to rank
        
        Returns:
            {
                "query": "...",
                "count": 27,
                "ranked": [
                    {"text": "...", "similarity": 0.92},
                    {"text": "...", "similarity": 0.87},
                    ...
                ]
            }
        """
        
        if not query_text or not candidate_texts:
            return {"error": "Empty query or candidates"}
        
        if len(candidate_texts) > self.MAX_BATCH_SIZE:
            return {"error": f"Too many candidates ({len(candidate_texts)} > {self.MAX_BATCH_SIZE})"}
        
        if len(query_text) > self.MAX_TEXT_LENGTH:
            return {"error": f"Query exceeds max length ({self.MAX_TEXT_LENGTH})"}
        
        if not self.model:
            return {"error": "Model not loaded"}
        
        try:
            # Encode all
            all_texts = [query_text] + candidate_texts
            embeddings = self.model.encode(all_texts, convert_to_tensor=True)
            
            query_embedding = embeddings[0]
            candidate_embeddings = embeddings[1:]
            
            # Calculate similarities
            similarities = util.pytorch_cos_sim(query_embedding, candidate_embeddings)[0].cpu().numpy()
            
            # Create ranked results (highest first)
            ranked = []
            for text, score in zip(candidate_texts, similarities):
                ranked.append({
                    "text": text,
                    "similarity": float(score)
                })
            
            ranked.sort(key=lambda x: x["similarity"], reverse=True)
            
            return {
                "query": query_text,
                "count": len(ranked),
                "ranked": ranked,
                "note": "System applies threshold, limits, balancing next"
            }
        except Exception as e:
            logger.error(f"Batch similarity failed: {e}")
            return {
                "query": query_text,
                "error": str(e)
            }


# Singleton instance
_embedding_service: Optional[EmbeddingService] = None


def get_embedding_service() -> EmbeddingService:
    """Get or create singleton service."""
    global _embedding_service
    if _embedding_service is None:
        _embedding_service = EmbeddingService()
    return _embedding_service
