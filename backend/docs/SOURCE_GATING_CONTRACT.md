# Source Gating Contract

## Purpose

Detta dokument definierar det normativa API-kontraktet for backend-driven source gating.

## Scope (Fas 1)

- Kalla: `calendar`
- Freshness TTL: 24 timmar
- Auto-retry i klient: exakt en gang per fraga
- Retrieval-kontrakt: oforandrat (strict embedding-`503`)

## `POST /query`

### Request compatibility

Begäran ar bakatkompatibel:
- `{ "query": "..." }`
- `{ "question": "..." }`

### Response additions (top-level)

| Field | Meaning |
| --- | --- |
| `analysis_ready` | `true` nar tillracklig feature-data finns |
| `requires_sources` | lista over kallor som behovs |
| `requirement_reason_codes` | maskinlasbara orsaker till databehov |
| `required_time_window` | exakt tidsfonster klienten ska hamta |

### Semantics

- Analytics med komplett data:
  - `analysis_ready=true`
  - `requires_sources=[]`
- Analytics med saknad/stale/coverage-gap:
  - `analysis_ready=false`
  - `requires_sources=["calendar"]`
  - `requirement_reason_codes` satt
- Retrieval-svar:
  - `analysis_ready=true`
  - `requires_sources=[]`

### Reason codes (Fas 1)

- `calendar_data_missing`
- `calendar_data_stale`
- `calendar_coverage_gap`

### `required_time_window`

Format:

```json
{
  "start": "2026-02-16T00:00:00Z",
  "end": "2026-02-16T23:59:59Z",
  "granularity": "day"
}
```

Regel: iOS ska hamta features for detta fonster och inte bredare, om inte klienten explicit kor proaktiv refresh-policy.

## `GET /assistant/feature-status`

Returnerar feature-status per kalla (Fas 1: `calendar`):

```json
{
  "calendar": {
    "available": true,
    "last_updated": "2026-02-17T10:32:00Z",
    "coverage_start": "2026-01-01T00:00:00Z",
    "coverage_end": "2026-12-31T23:59:59Z",
    "coverage_days": 365,
    "snapshot_count": 412,
    "fresh": true,
    "freshness_ttl_hours": 24
  }
}
```

## `POST /ingest`

Begaran ar bakatkompatibel:
- legacy: endast `items`
- utokat: `items` + optional `features.calendar_events`

Exempel:

```json
{
  "items": [],
  "features": {
    "calendar_events": [
      {
        "id": "calendar:evt_123:2026-03-19T09:00:00Z",
        "event_identifier": "evt_123",
        "title": "Mote",
        "notes": "Sprintplanering",
        "location": "Kontor",
        "start_at": "2026-03-19T09:00:00Z",
        "end_at": "2026-03-19T10:00:00Z",
        "is_all_day": false,
        "calendar_title": "Work",
        "last_modified_at": "2026-03-18T18:10:00Z",
        "snapshot_hash": "sha256:..."
      }
    ]
  }
}
```

Upsert-regel: samma `id` uppdateras endast nar `snapshot_hash` andrats.

## Error Behavior

- Retrieval/embedding-dependent fragor:
  - embedding-backend nere -> `503`
- Analytics-fragor:
  - ska inte bero pa embeddings
  - returnerar `200` med source-gating-signaler vid databehov

## Compliance Rules

- Ingen bakgrundsspegel av systemappar.
- Datahamtning ar fragedriven eller explicit foreground-refresh.
- Klienten far inte retry-loopa; max en auto-retry per fraga.
