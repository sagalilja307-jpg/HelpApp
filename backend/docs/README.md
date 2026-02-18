# Backend Documentation

This directory contains documentation for the HelpersHelp backend.

## Documents

### [STRUCTURE.md](STRUCTURE.md)
Backend architecture and module organization.

### [MODEL_VERIFICATION.md](MODEL_VERIFICATION.md)
AI model verification guide (Ollama embeddings + generation).

### [INSIGHT_QUERY_ARCHITECTURE.md](INSIGHT_QUERY_ARCHITECTURE.md)
Snapshot DataIntent v1 query model and responsibilities.

### [ADDING_NEW_SOURCE.md](ADDING_NEW_SOURCE.md)
Playbook for adding new snapshot sources in DataIntent v1.

### [SOURCE_GATING_CONTRACT.md](SOURCE_GATING_CONTRACT.md)
Deprecated in v1. Kept for historical reference.

## Quick Links

1. [Backend README](../README.md)
2. [STRUCTURE.md](STRUCTURE.md)
3. [MODEL_VERIFICATION.md](MODEL_VERIFICATION.md)
4. [INSIGHT_QUERY_ARCHITECTURE.md](INSIGHT_QUERY_ARCHITECTURE.md)
5. [ADDING_NEW_SOURCE.md](ADDING_NEW_SOURCE.md)
6. [Snapshot DataIntent v1 rules](../../docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md)

## Start Backend (canonical flow)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
uvicorn api:app --reload
```

## Run Tests

```bash
cd backend
source .venv/bin/activate
pytest
```

## Documentation Standards

- Keep docs aligned with Snapshot DataIntent v1 rules.
- Update `docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md` when changing query behavior.
- Avoid references to deprecated source-gating or feature-store flows.
