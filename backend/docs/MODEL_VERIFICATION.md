# Model Verification Guide

This guide verifies the two model adapters used by backend:

- BGE-M3 embeddings
- Ollama text generation

## Prerequisites

```bash
cd backend
pip install -e .
```

## 1) Verify BGE-M3 adapter

Quick check:

```bash
python tools/test_bge_m3.py
```

Manual check:

```python
from helpershelp.infrastructure.llm.bge_m3_adapter import get_embedding_service

svc = get_embedding_service()
result = svc.embed_text("Detta ar ett test")
print(result.get("embedding_dim"))
```

Expected:

- adapter import works
- embedding result contains vector dimension (typically 1024)

## 2) Verify Ollama adapter

Install/start Ollama:

```bash
# macOS
brew install ollama
ollama serve
ollama pull qwen2.5:7b
```

Manual check:

```python
from helpershelp.application.llm.text_generation_service import get_text_generation_service

svc = get_text_generation_service()
print(svc.model_available)
```

## 3) End-to-end backend smoke

Start API:

```bash
uvicorn api:app --reload
```

Then call query endpoint:

```bash
curl -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{"query":"Sammanfatta mina mejl idag","language":"sv","sources":["assistant_store"],"days":1}'
```

## Environment variables

- `OLLAMA_HOST` (default `http://localhost:11434`)
- `OLLAMA_MODEL` (default `qwen2.5:7b`)
- `HELPERSHELP_OFFLINE` (`1` enables offline model mode)
- `BGE_M3_LOCAL_PATH` (optional local model path)
- `HELPERSHELP_MODEL_CACHE_DIR` (model cache location)

## Important note

Do not use removed shim imports from old docs/examples, such as `helpershelp.llm.embedding_service`.
Use canonical paths under `helpershelp.infrastructure.llm.*` and `helpershelp.application.llm.*`.
