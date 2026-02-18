# HelpersHelp Backend

FastAPI-backend i monorepot, paketerad som `helpershelp` med `src/`-layout.

## Snapshot DataIntent v1

- `POST /query` returnerar alltid `{ "data_intent": { ... } }`.
- `/query` ar deterministisk intent-routing, utan analytics, embeddings eller retrieval.
- `POST /ingest` accepterar `items` och validerar bort legacy-falt.
- `/llm/*`-endpoints finns inte i backenden.

## Quick Links

- [Backend Structure](docs/STRUCTURE.md)
- [Insight Query Architecture](docs/INSIGHT_QUERY_ARCHITECTURE.md)
- [Adding New Source](docs/ADDING_NEW_SOURCE.md)
- [Backend Verification](docs/MODEL_VERIFICATION.md)
- [API Docs](http://localhost:8000/docs)

## Struktur

- `api.py` - uvicorn-entrypoint (`uvicorn api:app --reload`)
- `src/helpershelp/` - all backendkod
- `tests/` - unittest/contract-suite
- `docs/` - backend-specifik dokumentation
- `tools/ngrok/example.py` - enkelt ngrok-exempel for lokala demos

## Setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
```

## Kor API

```bash
cd backend
source .venv/bin/activate
uvicorn api:app --reload
```

## Kor tester

```bash
cd backend
source .venv/bin/activate
pytest -q
```

## Viktiga kontrakt

### `POST /query`

- Request: `query|question`, `language`, optional `days`, `sources`, `data_filter`.
- Response: exakt ett toppniva-falt `data_intent`.
- Timeframe i `data_intent` ar alltid ISO8601 med timezone och granularity ar `day|week|month|custom`.

### `POST /ingest`

- Stodjer endast `items` i request-kontraktet.
- Legacy payload-falt valideras bort (422).
- Response innehaller:
  - `status`
  - `inserted`
  - `updated`

### `GET /health/details`

Returnerar endast runtime-falt for aktuell backend:

- `status`
- `timestamp`
- `db_path`
- `sync_loop_enabled`

## Stodnivaer och adaptation

- `assistant.support.level` (`0..3`) ar grundintensitet (default `1`).
- `assistant.support.paused` pausar interventioner utan att andra niva.
- `assistant.support.adaptation_enabled` styr om larda vikter far uppdateras.
- `assistant.support.time_critical_hours` default `24`.
- `assistant.support.daily_caps` default `{"0":0,"1":2,"2":3,"3":5}`.

Typed endpoints:

- `GET /settings/support`
- `POST /settings/support`
- `GET /settings/learning`
- `POST /settings/learning/pause`
- `POST /settings/learning/reset`

## Databas

- Default DB: `backend/data/helpershelp.db`
- Override: `HELPERSHELP_DB_PATH=/absolut/eller/relativ/sokvag.db`

## Ngrok (lokal installation)

Repo:t innehaller inte ngrok-binaren.

Exempelinstallation:

- macOS (Homebrew): `brew install ngrok/ngrok/ngrok`
- eller ladda ner fran [ngrok.com](https://ngrok.com/download)
