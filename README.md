# Helper Monorepo

Monorepot innehåller iOS-appen och backend i en tydlig struktur. Systemet är nu renodlat till att enbart hantera "query" och "mail".

## Struktur
- `ios/` – iOS-projektet (`ios/Helper.xcodeproj`)
- `backend/` – FastAPI-backend för query och mail (`uvicorn api:app --reload`)

## Snabbstart: iOS
1. Öppna `ios/Helper.xcodeproj` i Xcode.
2. Kör scheme `Helper`.

## Snabbstart: backend
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
uvicorn api:app --reload
```

## Start/Stop: backend

Starta backend (lyssna på alla interfaces):
```bash
cd backend
source .venv/bin/activate
uvicorn api:app --host 0.0.0.0 --port 8000
```

Stäng av backend:
```bash
pkill -f "uvicorn api:app"
```

## Test: backend
```bash
cd backend
source .venv/bin/activate
pytest -q
```
