# HelpersHelp Backend

FastAPI-backend i monorepot, paketerad som `helpershelp` med `src/`-layout. Systemet hanterar enbart `query` och `mail` integration. All tidigare assistent-infrastruktur är borttagen.

## Core Features

- **Query**: Deterministisk intent-routing (`POST /query`) för kalender, mail, kontakter, etc.
- **Mail**: API:er för e-posthämtning.
- **Auth**: OAuth Authorization code exchange och token hantering (`oauth_gmail`).

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
