# Backend Documentation

Dokumentationen i den har mappen beskriver nuvarande Snapshot DataIntent v1-backend.

## Canonical Documents

1. [STRUCTURE.md](STRUCTURE.md) - backendens modulstruktur och lager.
2. [INSIGHT_QUERY_ARCHITECTURE.md](INSIGHT_QUERY_ARCHITECTURE.md) - `/query` och DataIntent-router.
3. [ADDING_NEW_SOURCE.md](ADDING_NEW_SOURCE.md) - playbook for nya snapshot-kallor.
4. [MODEL_VERIFICATION.md](MODEL_VERIFICATION.md) - verifieringssteg for API-kontrakt och testsvit.
5. [CLEAN_ARCHITECTURE.md](CLEAN_ARCHITECTURE.md) - designprinciper.

## Related Monorepo Docs

- [Root README](../../README.md)
- [Snapshot DataIntent v1 rules](../../docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md)
- [Snapshot DataIntent v1 sequence](../../docs/architecture/SNAPSHOT_DATAINTENT_V1_SEQUENCE.md)

## Local Commands

Start backend:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
uvicorn api:app --reload
```

Run tests:

```bash
cd backend
source .venv/bin/activate
pytest -q
```

## Documentation Rules

- Hall dokumentation alignad med Snapshot DataIntent v1.
- Uppdatera `docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md` vid kontraktsandringar i `/query`.
- Beskriv endast aktiv kodvag, inte borttagna legacy-floden.
