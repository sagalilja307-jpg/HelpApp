# HelpersHelp Backend

FastAPI-backend i monorepot, paketerad som `helpershelp` med `src/`-layout. Systemet hanterar deterministisk query-routing och supportinställningar. All tidigare assistent-infrastruktur är borttagen.

## Core Features

- **Query**: Deterministisk intent-routing (`POST /query`) för kalender, mail, kontakter, etc.
- **System**: Health-endpoints (`/health`, `/healthz`, `/health/details`).
- **Settings**: Support- och lärinställningar (`/settings/*`).

## Struktur

- `api.py` - uvicorn-entrypoint (`uvicorn api:app --reload`)
- `src/helpershelp/` - all backendkod
- `tests/` - unittest/contract-suite

## Setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
```

## Kör API

```bash
cd backend
source .venv/bin/activate
uvicorn api:app --reload
```

## Kör tester

```bash
cd backend
source .venv/bin/activate
pytest -q
```

## Databas

- Default DB: `backend/data/helpershelp.db`
- Override: `HELPERSHELP_DB_PATH=/absolut/eller/relativ/sökväg.db`
