#!/usr/bin/env python3
"""
Test script to verify Ollama BGE-M3 embedding functionality.

This script checks:
1. Ollama reachability
2. Embedding model availability
3. Basic embedding functionality
4. Similarity calculation
"""

import os
import sys
from pathlib import Path

if __name__ != "__main__":
    import pytest

    pytest.skip("Manual embedding verification tool (not a unit test).", allow_module_level=True)

# Add backend src to path
backend_dir = Path(__file__).parent.parent
sys.path.insert(0, str(backend_dir / "src"))


def test_embedding_service():
    """Test if EmbeddingService can be instantiated and model is available."""
    print("=" * 60)
    print("1. Testing EmbeddingService (Ollama)")
    print("=" * 60)

    try:
        from helpershelp.infrastructure.llm.bge_m3_adapter import get_embedding_service
    except ImportError as e:
        print(f"✗ Failed to import EmbeddingService: {e}")
        return None

    service = get_embedding_service()
    status = service.get_runtime_status()

    print(f"  Ollama host: {status['ollama_host']}")
    print(f"  Embedding model: {status['embedding_model']}")
    print(f"  Active endpoint: {status['active_embed_endpoint']}")

    if not status.get("ollama_reachable"):
        print("✗ Ollama is not reachable")
        print("\nStart Ollama with:")
        print("  ollama serve")
        return None

    if not status.get("model_available"):
        print(f"✗ Embedding model not available: {status['embedding_model']}")
        print(f"  Missing models: {status.get('missing_models', [])}")
        print("\nPull model with:")
        print(f"  ollama pull {status['embedding_model']}")
        return None

    print("✓ Ollama embedding service is available")
    print()
    return service


def test_embedding_functionality(service):
    """Test basic embedding functionality."""
    print("=" * 60)
    print("2. Testing Embedding Functionality")
    print("=" * 60)

    # Test single text embedding
    print("\nTest 2.1: Single text embedding")
    test_text = "Detta är ett test av embedding-modellen"
    result = service.embed_text(test_text)

    if "error" in result:
        print(f"✗ Embedding failed: {result['error']}")
        return False

    embedding_dim = result.get("embedding_dim", 0)
    print("✓ Text embedded successfully")
    print(f"  Embedding dimension: {embedding_dim}")

    if embedding_dim != 1024:
        print(f"✗ Expected 1024 dimensions, got {embedding_dim}")
        return False

    # Test batch embedding
    print("\nTest 2.2: Batch embedding")
    test_texts = [
        "Första texten",
        "Andra texten",
        "Tredje texten",
    ]
    result = service.embed_batch(test_texts)

    if "error" in result:
        print(f"✗ Batch embedding failed: {result['error']}")
        return False

    print("✓ Batch embedding successful")
    print(f"  Number of embeddings: {result.get('count', 0)}")
    print(f"  Embedding dimension: {result.get('embedding_dim', 0)}")

    # Test similarity
    print("\nTest 2.3: Similarity calculation")
    text1 = "Jag gillar att programmera i Python"
    text2 = "Python är mitt favoritspråk för programmering"
    text3 = "Jag äter gärna pizza"

    result1 = service.similarity(text1, text2)
    result2 = service.similarity(text1, text3)

    if "error" in result1 or "error" in result2:
        print("✗ Similarity calculation failed")
        print(result1.get("error") or result2.get("error"))
        return False

    sim1 = result1.get("similarity", 0.0)
    sim2 = result2.get("similarity", 0.0)

    print(f"✓ Similarity calculation successful")
    print(f"  Related texts similarity: {sim1:.3f}")
    print(f"  Unrelated texts similarity: {sim2:.3f}")
    return True


def main():
    print("\n" + "=" * 60)
    print("Ollama BGE-M3 Embedding Test Suite")
    print("=" * 60)
    print()

    print("Configuration:")
    print(f"  OLLAMA_HOST: {os.getenv('OLLAMA_HOST', 'http://localhost:11434')}")
    print(f"  OLLAMA_EMBED_MODEL: {os.getenv('OLLAMA_EMBED_MODEL', 'bge-m3')}")
    print()

    service = test_embedding_service()
    if service is None:
        print("\n❌ Embedding service initialization failed")
        sys.exit(1)

    if not test_embedding_functionality(service):
        print("\n❌ Functionality tests failed")
        sys.exit(1)

    print()
    print("=" * 60)
    print("✅ All tests passed!")
    print("=" * 60)


if __name__ == "__main__":
    main()
