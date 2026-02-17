#!/usr/bin/env python3
"""
Test script to verify BGE-M3 embedding model functionality.

This script checks:
1. If sentence-transformers is installed
2. If the BGE-M3 model can be loaded
3. Basic embedding functionality
4. Similarity calculation
"""

import sys
import os
from pathlib import Path

# Add backend src to path
backend_dir = Path(__file__).parent.parent
sys.path.insert(0, str(backend_dir / "src"))

def test_imports():
    """Test if required packages are available."""
    print("=" * 60)
    print("1. Testing Imports")
    print("=" * 60)
    
    try:
        import sentence_transformers
        print(f"✓ sentence-transformers: {sentence_transformers.__version__}")
    except ImportError as e:
        print(f"✗ sentence-transformers not available: {e}")
        print("\nInstall with: pip install sentence-transformers")
        return False
    
    try:
        import torch
        print(f"✓ torch: {torch.__version__}")
    except ImportError as e:
        print(f"✗ torch not available: {e}")
        return False
    
    print()
    return True


def test_embedding_service():
    """Test if EmbeddingService can be instantiated."""
    print("=" * 60)
    print("2. Testing EmbeddingService")
    print("=" * 60)
    
    try:
        from helpershelp.infrastructure.llm.bge_m3_adapter import EmbeddingService
        print("✓ EmbeddingService imported successfully")
    except ImportError as e:
        print(f"✗ Failed to import EmbeddingService: {e}")
        return False
    
    print("\nInitializing EmbeddingService...")
    print("(This may take a moment if the model needs to be downloaded)")
    print()
    
    try:
        service = EmbeddingService()
        
        if service.model is None:
            print("⚠️  BGE-M3 model not loaded - running in degraded mode")
            print("\nPossible reasons:")
            print("  - Model not found in cache")
            print("  - HELPERSHELP_OFFLINE=1 but model not downloaded")
            print("\nTo download the model:")
            print("  1. Set HELPERSHELP_OFFLINE=0 (or unset)")
            print("  2. Run this script again")
            print("  3. The model will be downloaded automatically")
            return False
        else:
            print("✓ BGE-M3 model loaded successfully")
            print()
            return True
            
    except Exception as e:
        print(f"✗ Failed to initialize EmbeddingService: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_embedding_functionality(service):
    """Test basic embedding functionality."""
    print("=" * 60)
    print("3. Testing Embedding Functionality")
    print("=" * 60)
    
    # Test single text embedding
    print("\nTest 3.1: Single text embedding")
    test_text = "Detta är ett test av embedding-modellen"
    
    try:
        result = service.embed_text(test_text)
        
        if "error" in result:
            print(f"✗ Embedding failed: {result['error']}")
            return False
        
        embedding_dim = result.get("embedding_dim", 0)
        print(f"✓ Text embedded successfully")
        print(f"  Text: '{test_text}'")
        print(f"  Embedding dimension: {embedding_dim}")
        
        if embedding_dim != 1024:
            print(f"⚠️  Expected 1024 dimensions, got {embedding_dim}")
        
    except Exception as e:
        print(f"✗ Embedding test failed: {e}")
        return False
    
    # Test batch embedding
    print("\nTest 3.2: Batch embedding")
    test_texts = [
        "Första texten",
        "Andra texten",
        "Tredje texten"
    ]
    
    try:
        result = service.embed_batch(test_texts)
        
        if "error" in result:
            print(f"✗ Batch embedding failed: {result['error']}")
            return False
        
        count = result.get("count", 0)
        print(f"✓ Batch embedded successfully")
        print(f"  Number of texts: {len(test_texts)}")
        print(f"  Number of embeddings: {count}")
        
    except Exception as e:
        print(f"✗ Batch embedding test failed: {e}")
        return False
    
    # Test similarity
    print("\nTest 3.3: Similarity calculation")
    text1 = "Jag gillar att programmera i Python"
    text2 = "Python är mitt favoritspråk för programmering"
    text3 = "Jag äter gärna pizza"
    
    try:
        result1 = service.similarity(text1, text2)
        result2 = service.similarity(text1, text3)
        
        if "error" in result1 or "error" in result2:
            print(f"✗ Similarity calculation failed")
            return False
        
        sim1 = result1.get("similarity", 0)
        sim2 = result2.get("similarity", 0)
        
        print(f"✓ Similarity calculation successful")
        print(f"  '{text1[:40]}...'")
        print(f"  vs '{text2[:40]}...'")
        print(f"  Similarity: {sim1:.3f}")
        print()
        print(f"  '{text1[:40]}...'")
        print(f"  vs '{text3[:40]}...'")
        print(f"  Similarity: {sim2:.3f}")
        
        if sim1 > sim2:
            print(f"\n✓ Semantic similarity works correctly (related texts have higher similarity)")
        else:
            print(f"\n⚠️  Unexpected: unrelated texts have higher similarity")
        
    except Exception as e:
        print(f"✗ Similarity test failed: {e}")
        return False
    
    print()
    return True


def main():
    """Run all tests."""
    print("\n" + "=" * 60)
    print("BGE-M3 Embedding Model Test Suite")
    print("=" * 60)
    print()
    
    # Show configuration
    print("Configuration:")
    print(f"  HELPERSHELP_OFFLINE: {os.getenv('HELPERSHELP_OFFLINE', '0')}")
    print(f"  BGE_M3_LOCAL_PATH: {os.getenv('BGE_M3_LOCAL_PATH', 'not set')}")
    print()
    
    # Run tests
    if not test_imports():
        print("\n❌ Import tests failed")
        sys.exit(1)
    
    service_ok = test_embedding_service()
    
    if not service_ok:
        print("\n❌ Embedding service initialization failed")
        sys.exit(1)
    
    # Get the service for functionality tests
    from helpershelp.infrastructure.llm.bge_m3_adapter import get_embedding_service
    service = get_embedding_service()
    
    if not test_embedding_functionality(service):
        print("\n❌ Functionality tests failed")
        sys.exit(1)
    
    print("=" * 60)
    print("✅ All tests passed!")
    print("=" * 60)
    print()


if __name__ == "__main__":
    main()
