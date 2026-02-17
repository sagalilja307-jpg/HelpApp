# HelpersHelp Backend

FastAPI backend in the monorepo, packaged as `helpershelp` with `src/` layout.

## Status (2026-02-17)

Backward-compatibility shim modules have been removed from backend code.
This is an intentional internal breaking change.

Removed shim import paths:

| Removed path | Canonical path |
|---|---|
| `helpershelp.assistant.sync` | `helpershelp.application.assistant.sync` |
| `helpershelp.llm.embedding_service` | `helpershelp.infrastructure.llm.bge_m3_adapter` |
| `helpershelp.llm.llm_service` | `helpershelp.application.llm.llm_service` |
| `helpershelp.llm.ollama_service` | `helpershelp.infrastructure.llm.ollama_adapter` |
| `helpershelp.llm.text_generation_service` | `helpershelp.application.llm.text_generation_service` |
| `helpershelp.mail.oauth_service` | `helpershelp.infrastructure.security.oauth_adapter` |
| `helpershelp.mail.mail_query_service` | `helpershelp.application.mail.mail_query_service` |

Also removed as invalid path usage:

- `helpershelp.assistant.support` -> use `helpershelp.application.assistant.support`

## Quick links

- `docs/STRUCTURE.md` - current backend structure
- `docs/CLEAN_ARCHITECTURE.md` - architecture boundaries and dependency rules
- `docs/SHIM_DEPRECATION_STRATEGY.md` - completed shim removal strategy
- `docs/SHIM_AUDIT_SUMMARY.md` - final audit and verification
- `docs/MODEL_VERIFICATION.md` - BGE-M3 and Ollama checks

## Structure

- `api.py` - uvicorn entrypoint shim (`uvicorn api:app --reload`)
- `src/helpershelp/` - backend package
- `tests/` - test suite
- `tools/` - local checks and helper scripts

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

## Run API

```bash
uvicorn api:app --reload
```

## Run tests

```bash
pytest
```

## Run shim/architecture checks

```bash
python tools/check_shim_imports.py
python tools/enforce_architecture.py
```

## Smoke import

```bash
python -c "from helpershelp.api.app import app; print('OK')"
```

## Model configuration

### BGE-M3 embeddings

- Default cache: `backend/.model_cache/`
- `HELPERSHELP_OFFLINE=1` enables offline mode
- `BGE_M3_LOCAL_PATH=/path/to/model` forces local model path

### Ollama text generation

- `OLLAMA_HOST` default: `http://localhost:11434`
- `OLLAMA_MODEL` default: `qwen2.5:7b`

## Notes about iOS integration

The iOS app integrates with backend via HTTP endpoints (for example `/query`, `/sync/gmail`).
There is no iOS Python binding to `helpershelp` imports.

## Database

- Default DB: `backend/data/helpershelp.db`
- Override: `HELPERSHELP_DB_PATH=/absolute/or/relative/path.db`
