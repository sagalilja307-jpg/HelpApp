# HelpersHelp Backend

FastAPI-backend i monorepot, paketerad som `helpershelp` med `src/`-layout.

> ℹ️ **Status:** Shim-importer är borttagna.  
> Använd canonical imports enligt [Shim Deprecation Strategy](docs/SHIM_DEPRECATION_STRATEGY.md).

## Quick Links

- 📋 **[Architecture Guide](docs/STRUCTURE.md)** - Complete backend structure and organization
- 🏗️ **[Clean Architecture](docs/CLEAN_ARCHITECTURE.md)** - Architecture principles and patterns
- 🔄 **[Shim Deprecation Strategy](docs/SHIM_DEPRECATION_STRATEGY.md)** - Migration guide for legacy imports
- 🔍 **[Model Verification](docs/MODEL_VERIFICATION.md)** - Test Ollama generation + embeddings
- 📚 **[API Documentation](http://localhost:8000/docs)** - Interactive API docs (when running)

## Struktur
- `api.py` – uvicorn-entrypoint shim (`uvicorn api:app --reload`)
- `src/helpershelp/` – all backendkod
- `tests/` – unittest-suite
- `tools/ngrok/example.py` – lokalt ngrok-exempel

## Setup
```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
```

## Model Configuration

This backend is **Ollama-only** for all model inference:
- **Generation:** `qwen2.5:7b`
- **Embeddings:** `bge-m3`

### Installation

1. Install Ollama:
   - macOS: `brew install ollama`
   - Linux: `curl -fsSL https://ollama.com/install.sh | sh`
   - Or download from [ollama.com](https://ollama.com/download)

2. Start Ollama server:
   ```bash
   ollama serve
   ```

3. Pull both required models:
   ```bash
   ollama pull qwen2.5:7b
   ollama pull bge-m3
   ```

### Configuration

Environment variables:
- `OLLAMA_HOST` - Ollama server URL (default: `http://localhost:11434`)
- `OLLAMA_MODEL` - Generation model (default: `qwen2.5:7b`)
- `OLLAMA_EMBED_MODEL` - Embedding model (default: `bge-m3`)

### Hardware Requirements

- **RAM**: Minimum 8GB, recommended 16GB for stable generation + embeddings
- **CPU**: Multi-core processor recommended
- **Disk**: ~8-10GB for both models

### Notes

- Ollama runs locally - no API keys required
- First inference may be slow (model loading)
- Embedding-dependent endpoints return `503` when Ollama embeddings are unavailable

## Kör API
```bash
uvicorn api:app --reload
```

## Kör tester
```bash
pytest
```

## Verify Models

To verify that Ollama generation and embeddings are working correctly:

```bash
# Test Ollama BGE-M3 embedding model
python tools/test_bge_m3.py

# Test Ollama (requires ollama serve running)
curl http://localhost:11434/api/tags
```

See [docs/MODEL_VERIFICATION.md](docs/MODEL_VERIFICATION.md) for detailed verification guide.

## Stödnivåer och adaptation
- `assistant.support.level` (`0..3`) är grundintensitet (default `1`).
- `assistant.support.paused` pausar interventioner utan att ändra nivå.
- `assistant.support.adaptation_enabled` styr om lärda vikter får uppdateras.
- `assistant.support.time_critical_hours` default `24`.
- `assistant.support.daily_caps` default `{"0":0,"1":2,"2":3,"3":5}`.

### Typed endpoints
- `GET /settings/support`
- `POST /settings/support`
- `GET /settings/learning`
- `POST /settings/learning/pause`
- `POST /settings/learning/reset`

Notera:
- `/settings` (GET/POST) finns kvar för bakåtkompatibilitet.
- `learning/reset` återställer bara lärda vikter/mönster, inte vald stödnivå.

## Modellpolicy
- Ollama krävs för både generation och embeddings.
- Pulla modeller i förväg i driftmiljö med `ollama pull qwen2.5:7b` och `ollama pull bge-m3`.

## Databas
- Default DB: `backend/data/helpershelp.db`
- Override: `HELPERSHELP_DB_PATH=/absolut/eller/relativ/sökväg.db`

## Ngrok (lokal installation)
Repo:t innehåller inte ngrok-binären.

Exempelinstallation:
- macOS (Homebrew): `brew install ngrok/ngrok/ngrok`
- eller ladda ner från [ngrok.com](https://ngrok.com/download)
