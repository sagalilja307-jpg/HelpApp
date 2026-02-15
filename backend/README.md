# HelpersHelp Backend

FastAPI-backend i monorepot, paketerad som `helpershelp` med `src/`-layout.

## Struktur
- `api.py` – uvicorn-entrypoint shim (`uvicorn api:app --reload`)
- `src/helpershelp/` – all backendkod
- `tests/` – unittest-suite
- `tools/ngrok/example.py` – lokalt ngrok-exempel

## Setup
```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

## Ollama Setup (Required for Text Generation)

This backend uses **Ollama** with **Qwen2.5 7B** for text generation (replaced GPT-SW3).

### Installation

1. Install Ollama:
   - macOS: `brew install ollama`
   - Linux: `curl -fsSL https://ollama.com/install.sh | sh`
   - Or download from [ollama.com](https://ollama.com/download)

2. Start Ollama server:
   ```bash
   ollama serve
   ```

3. Pull the Qwen2.5 7B model:
   ```bash
   ollama pull qwen2.5:7b
   ```

### Configuration

Environment variables:
- `OLLAMA_HOST` - Ollama server URL (default: `http://localhost:11434`)
- `OLLAMA_MODEL` - Model to use (default: `qwen2.5:7b`)

### Hardware Requirements

- **RAM**: Minimum 8GB, recommended 16GB for optimal performance
- **CPU**: Multi-core processor recommended
- **Disk**: ~4.7GB for the Qwen2.5 7B model

### Notes

- Ollama runs locally - no API keys required
- First inference may be slow (model loading)
- If Ollama is unavailable, the backend falls back to placeholder mode

## Kör API
```bash
uvicorn api:app --reload
```

## Kör tester
```bash
python -m unittest discover -s tests -p 'test*.py'
```

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

## Modellpolicy: offline/online
- `HELPERSHELP_OFFLINE=1` aktiverar offline-läge (`HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`).
- Utan `HELPERSHELP_OFFLINE` körs online-default där modellvikter får laddas ned vid behov.
- Lokal cache styrs via `HELPERSHELP_MODEL_CACHE_DIR` (default: `backend/.model_cache`).

## Databas
- Default DB: `backend/data/helpershelp.db`
- Override: `HELPERSHELP_DB_PATH=/absolut/eller/relativ/sökväg.db`

## Ngrok (lokal installation)
Repo:t innehåller inte ngrok-binären.

Exempelinstallation:
- macOS (Homebrew): `brew install ngrok/ngrok/ngrok`
- eller ladda ner från [ngrok.com](https://ngrok.com/download)
