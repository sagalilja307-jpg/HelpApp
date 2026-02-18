# Model Verification Guide (Ollama-Only)

Det här dokumentet verifierar att backendens två modeller fungerar via **samma Ollama-instans**:
- Generation: `qwen2.5:7b`
- Embeddings: `bge-m3`

## Prerequisites

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
```

## 1. Installera och starta Ollama

```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.com/install.sh | sh

# Starta servern
ollama serve
```

I en ny terminal:

```bash
ollama pull qwen2.5:7b
ollama pull bge-m3
```

## 2. Verifiera embeddingmodellen (`bge-m3`)

```bash
python tools/test_bge_m3.py
```

Förväntat:
- Ollama reachable
- Embedding model available
- `embedding_dim = 1024`

## 3. Verifiera generation (`qwen2.5:7b`)

```bash
curl http://localhost:11434/api/generate -d '{
  "model": "qwen2.5:7b",
  "prompt": "Skriv en kort svensk sammanfattning om AI.",
  "stream": false
}'
```

## 4. Verifiera backendens health-status

Starta backend:

```bash
uvicorn api:app --reload
```

Kontrollera:

```bash
curl http://localhost:8000/health/details
```

Förväntat fält:
- `llm.generation_model`
- `llm.embedding_model`
- `llm.ollama_reachable`
- `llm.missing_models`

## 5. Full query-pipeline test

```bash
curl -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Sammanfatta mina mejl från idag",
    "language": "sv",
    "sources": ["assistant_store"],
    "days": 1
  }'
```

## Environment Variables

```bash
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=qwen2.5:7b
OLLAMA_EMBED_MODEL=bge-m3
```

## Troubleshooting

### Ollama unreachable
- Kontrollera att `ollama serve` körs.
- Testa: `curl http://localhost:11434/api/tags`.

### Embedding model missing
- Kör: `ollama pull bge-m3`.
- Kontrollera att `OLLAMA_EMBED_MODEL` matchar installerat modellnamn.

### Generation model missing
- Kör: `ollama pull qwen2.5:7b`.
- Kontrollera `OLLAMA_MODEL`.

### API returnerar 503 på embedding-endpoints/query
### API returnerar 503 på embedding-endpoints
- Backend signalerar att embedding-backend saknas.
- Åtgärda Ollama-reachability och model availability först.
