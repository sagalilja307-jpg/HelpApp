# Snapshot DataIntent v1 — Architecture Lock

This document is normative.
If code and this document diverge, code must be adjusted to match this document.

## 1) System Overview

Snapshot DataIntent v1 is a minimal query architecture:

1. iOS sends a user question to backend `/query`.
2. Backend returns **only** `data_intent` (no analytics).
3. iOS fetches data from the correct source.
4. iOS formats the response locally.

No analytics engine. No feature-store. No source-gating. No retry loops.

## 2) Snapshot Contract (Locked)

- `/query` returns always:
  - `{ "data_intent": { ... } }`
- Backend performs **intent classification only**.
- No analytics execution in v1.
- No source-gating fields in responses.
- No feature-store persistence.
- No embedding dependency for `/query`.
- No retry loop in client pipeline.

## 3) DataIntent v1 Schema (Normative)

```json
{
  "type": "object",
  "required": ["domain", "operation"],
  "properties": {
    "domain": {
      "type": "string",
      "enum": [
        "calendar",
        "reminders",
        "mail",
        "contacts",
        "photos",
        "files",
        "location",
        "notes",
        "system"
      ]
    },
    "operation": {
      "type": "string",
      "enum": ["list", "count", "next", "details", "search", "needs_clarification"]
    },
    "timeframe": {
      "type": "object",
      "required": ["start", "end", "granularity"],
      "properties": {
        "start": { "type": "string", "format": "date-time" },
        "end": { "type": "string", "format": "date-time" },
        "granularity": { "type": "string", "enum": ["day", "week", "month", "custom"] }
      }
    },
    "filters": {
      "type": "object",
      "additionalProperties": true
    },
    "sort": {
      "type": "object",
      "required": ["field", "direction"],
      "properties": {
        "field": { "type": "string" },
        "direction": { "type": "string", "enum": ["asc", "desc"] }
      }
    },
    "limit": { "type": "integer", "minimum": 1 },
    "fields": {
      "type": "array",
      "items": { "type": "string" }
    }
  }
}
```

## 4) Domain Routing Table (Locked)

| Domain    | Fetch location         |
| --------- | ---------------------- |
| calendar  | iOS EventKit           |
| reminders | iOS EventKit           |
| photos    | iOS PhotoKit           |
| contacts  | iOS CNContactStore     |
| location  | iOS CoreLocation       |
| notes     | iOS local store        |
| files     | iOS local/doc picker   |
| mail      | backend `/mail/*`      |

## 5) Ambiguity Rule (Locked)

Ambiguity is encoded in DataIntent:

```json
{
  "domain": "system",
  "operation": "needs_clarification",
  "filters": {
    "suggested_domains": ["calendar", "mail"]
  }
}
```

## 6) Invariants (Must Hold)

INVARIANTS:

1. Backend performs intent classification only.
2. Backend does not access system data.
3. Backend does not run analytics in v1.
4. `/query` never calls embeddings.
5. Snapshot engine never uses feature-store.
6. iOS contains no intent parsing logic.
7. Ambiguity is encoded as `domain="system"`.

## 7) Forbidden in v1

- Analytics execution in `/query`.
- Source-gating fields (`analysis_ready`, `requires_sources`, `requirement_reason_codes`, `required_time_window`).
- Feature-store persistence.
- Retry loops in query pipeline.
- Embedding dependency for `/query`.
- Client-side intent parsing.

## 8) Deprecated (Must Not Return)

- `/assistant/feature-status` endpoint.
- Feature snapshot tables (e.g., `calendar_feature_events`).
- `analysis` payloads in `/query` responses.

## 9) Reference

- `docs/architecture/SNAPSHOT_DATAINTENT_V1_SEQUENCE.md`
- `docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md`
