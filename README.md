# Helper Monorepo

Monorepot innehåller iOS-appen, backend och dokumentation i en tydlig struktur.

## Struktur
- `ios/` – iOS-projektet (`ios/Helper.xcodeproj`)
- `backend/` – FastAPI-backend (`uvicorn api:app --reload`)
- `docs/` – arkitektur och gemensam dokumentation
- `00_START_HERE/` – Finder-genvägar till de viktigaste delarna

## Snabbstart: iOS
1. Öppna `ios/Helper.xcodeproj` i Xcode.
2. Kör scheme `Helper`.

## Snabbstart: backend
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn api:app --reload
```

## Test: backend
```bash
cd backend
python -m unittest discover -s tests -p 'test*.py'
```
