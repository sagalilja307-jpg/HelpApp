# Backend Verification Guide

Detta dokument beskriver verifiering av nuvarande backend-kontrakt i Snapshot DataIntent v1.

## Prerequisites

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
```

## 1) Run full backend test suite

```bash
pytest -q
```

## 2) Verify `/query` contract manually

```bash
curl -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Hur manga olasta mejl har jag?",
    "language": "sv"
  }'
```

Expected shape:

```json
{
  "data_intent": {
    "domain": "mail",
    "operation": "count"
  }
}
```

## 3) Verify removed legacy endpoints

```bash
curl -i http://localhost:8000/llm/interpret-query
```

Expected: `404`.

## 4) Verify ingest contract

Valid request:

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"items":[]}'
```

Legacy payload should fail validation:

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"items":[],"features":{"calendar_events":[{"id":"evt-1"}]}}'
```

Expected: `422`.

## 5) Verify health details contract

```bash
curl http://localhost:8000/health/details
```

Expected fields:

- `status`
- `timestamp`
- `db_path`
- `sync_loop_enabled`
