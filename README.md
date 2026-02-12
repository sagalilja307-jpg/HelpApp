# Helper Monorepo

Monorepot innehåller iOS-appen, backend och dokumentation i en tydlig struktur.

## Struktur
- `ios/` – iOS-projektet (`ios/Helper.xcodeproj`)
- `backend/` – FastAPI-backend (`uvicorn api:app --reload`)
- `docs/` – arkitektur och gemensam dokumentation
- `00_START_HERE/` – Finder-genvägar till de viktigaste delarna

## Stabilitetsstandard (v1)
- Stödnivåer `0..3` styr intervention (backend är source-of-truth, iOS cachar lokalt).
- Default för ny användare: nivå `1`, adaptation på inom vald nivå.
- Tidskritisk signal följer 24h-fönster (event start, task/reminder due/overdue).
- Daglig nudgetak per nivå: `0/2/3/5`.
- Externa handlingar ska fortsätta följa `propose -> confirm -> execute`.

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
