# Model Verification Guide

This guide helps you verify that both AI models (BGE-M3 and Ollama Qwen2.5) are working correctly.

## Prerequisites

```bash
cd backend
pip install -e .
```

## 1. Verify BGE-M3 Embedding Model

BGE-M3 is used for semantic similarity and content ranking.

### Quick Test

```bash
python tools/test_bge_m3.py
```

**Expected Output:**
```
✓ sentence-transformers: [version]
✓ torch: [version]
✓ BGE-M3 model loaded successfully
✓ Text embedded successfully
  Embedding dimension: 1024
✅ All tests passed!
```

### Manual Verification

```python
from helpershelp.llm.embedding_service import get_embedding_service

service = get_embedding_service()

# Test embedding
result = service.embed_text("Detta är ett test")
print(f"Embedding dimension: {result['embedding_dim']}")  # Should be 1024

# Test similarity
result = service.similarity(
    "Jag gillar programmering",
    "Programmering är roligt"
)
print(f"Similarity: {result['similarity']:.3f}")  # Should be > 0.5
```

### Troubleshooting

**Model not found:**
- First run downloads ~2GB from Hugging Face
- Requires internet connection unless `HELPERSHELP_OFFLINE=1`
- Check `backend/.model_cache/` directory exists

**Out of memory:**
- BGE-M3 needs ~2GB RAM
- Close other applications
- Reduce batch size in code if needed

## 2. Verify Ollama Qwen2.5 Text Generation

Ollama is used for natural language generation and summarization.

### Installation

```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.com/install.sh | sh

# Start Ollama
ollama serve
```

### Pull Model

```bash
ollama pull qwen2.5:7b
```

### Quick Test

```bash
# In another terminal
curl http://localhost:11434/api/generate -d '{
  "model": "qwen2.5:7b",
  "prompt": "Skriv en kort sammanfattning om artificiell intelligens på svenska.",
  "stream": false
}'
```

### Backend Integration Test

```python
from helpershelp.llm.text_generation_service import get_text_generation_service

service = get_text_generation_service()

# Check if available
if service.model_available:
    print("✓ Ollama is connected")
else:
    print("✗ Ollama is not available")

# Test generation
result = service.generate_text(
    "Beskriv vad en hjälpassistent gör",
    max_length=100
)

if "error" not in result:
    print("✓ Text generation works")
    print(result["generated_text"])
else:
    print(f"✗ Error: {result['error']}")
```

### Troubleshooting

**Cannot connect to Ollama:**
- Check if `ollama serve` is running
- Verify `OLLAMA_HOST=http://localhost:11434`
- Test with: `curl http://localhost:11434/api/tags`

**Model not found:**
- Run `ollama list` to see installed models
- Pull model: `ollama pull qwen2.5:7b`
- Check model name matches `OLLAMA_MODEL` env var

**Slow inference:**
- First request is slower (model loading)
- Requires ~8GB RAM for 7B model
- Consider using smaller model: `ollama pull qwen2.5:3b`

## 3. Full System Test

Test the complete query pipeline:

```bash
# Start backend
uvicorn api:app --reload
```

Then in another terminal:

```bash
# Test query endpoint
curl -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Sammanfatta mina mejl från idag",
    "language": "sv",
    "sources": ["assistant_store"],
    "days": 1
  }'
```

**Expected behavior:**
1. Query is interpreted (BGE-M3 similarity)
2. Items are retrieved and ranked (BGE-M3)
3. Response is formulated (Ollama Qwen2.5)

## Environment Variables Summary

```bash
# Ollama
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=qwen2.5:7b

# BGE-M3
BGE_M3_LOCAL_PATH=/custom/path/to/model  # optional
HELPERSHELP_OFFLINE=0  # set to 1 for offline mode

# General
HELPERSHELP_MODEL_CACHE_DIR=.model_cache
```

## Health Check Endpoint

```bash
curl http://localhost:8000/health/details
```

**Expected output:**
```json
{
  "status": "ok",
  "timestamp": "2024-...",
  "model": {
    "embedding": "bge-m3",
    "generation": "qwen2.5:7b (Ollama)"
  }
}
```

## Performance Benchmarks

**BGE-M3:**
- Single embedding: ~50-100ms (CPU)
- Batch of 10: ~200-300ms (CPU)
- Memory: ~2GB

**Ollama Qwen2.5 7B:**
- First request: ~5-10 seconds (model loading)
- Subsequent requests: ~1-3 seconds
- Memory: ~8GB

## Fallback Behavior

If models are unavailable, the system falls back to "placeholder mode":
- BGE-M3 unavailable → Returns error for embedding operations
- Ollama unavailable → Returns simple text extraction without generation

Both failures are logged with warnings but don't crash the system.
