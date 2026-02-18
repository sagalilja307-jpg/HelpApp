# Backend Structure Documentation

## Overview

HelpersHelp-backenden ar organiserad i tydliga lager med en deterministisk Snapshot DataIntent v1-queryvag.

```
backend/
├── api.py
├── pyproject.toml
├── README.md
├── docs/
│   ├── STRUCTURE.md
│   ├── INSIGHT_QUERY_ARCHITECTURE.md
│   ├── ADDING_NEW_SOURCE.md
│   ├── MODEL_VERIFICATION.md
│   └── CLEAN_ARCHITECTURE.md
├── src/helpershelp/
│   ├── api/
│   │   ├── app.py
│   │   ├── deps.py
│   │   ├── models.py
│   │   └── routes/
│   │       ├── assistant.py
│   │       ├── auth.py
│   │       ├── health.py
│   │       ├── mail.py
│   │       ├── oauth_gmail.py
│   │       ├── query.py
│   │       └── sync.py
│   ├── application/
│   │   ├── assistant/
│   │   │   ├── proposals.py
│   │   │   ├── support.py
│   │   │   └── sync.py
│   │   ├── mail/
│   │   │   └── mail_query_service.py
│   │   └── query/
│   │       ├── data_intent_router.py
│   │       └── timeframe_resolver.py
│   ├── assistant/
│   ├── domain/
│   │   ├── models/
│   │   ├── rules/
│   │   └── value_objects/
│   │       └── time_utils.py
│   ├── infrastructure/
│   │   ├── persistence/sqlite_storage.py
│   │   └── security/
│   └── mail/
└── tests/
```

## Layer Responsibilities

### 1. API Layer (`src/helpershelp/api/`)

- FastAPI app setup, exception handling och route-registrering.
- Pydantic request/response-modeller i `models.py`.
- Tunna route-handlers; affarslogik ligger i application/domain.

### 2. Query Layer (`src/helpershelp/application/query/`)

- `data_intent_router.py`: deterministisk tolkning av fraga till `data_intent`.
- `timeframe_resolver.py`: central timeframe-upplosning (day/week/month/custom).
- `/query` returnerar endast `data_intent` och anropar inte embeddings/retrieval.

### 3. Assistant Layer (`src/helpershelp/application/assistant/` + `src/helpershelp/assistant/`)

- Dashboard/proposals/scoring/support-policy.
- Sync-loop och assistant-store integration.
- Typed support/learning settings.

### 4. Mail Layer (`src/helpershelp/application/mail/` + `src/helpershelp/mail/`)

- Provider-abstraktion, OAuth och mail-query.
- Maildata via `/mail/*` endpoints.

### 5. Domain + Infrastructure

- Domain innehaller modeller, regler och tids-vardeobjekt.
- Infrastructure innehaller persistence (`sqlite_storage.py`) och security adapters.

## Query Data Flow (v1)

```
HTTP POST /query
  -> api/routes/query.py
  -> application/query/data_intent_router.py
  -> application/query/timeframe_resolver.py
  -> response { "data_intent": ... }
```

## Guardrails

- Ingen `/llm/*`-yta i API:t.
- Ingen analytics/source-gating call path i `/query`.
- Timeframe output ska vara ISO8601 med explicit timezone.
- Granularity ska vara en av: `day`, `week`, `month`, `custom`.

## Verification

```bash
cd backend
source .venv/bin/activate
pytest -q
```
