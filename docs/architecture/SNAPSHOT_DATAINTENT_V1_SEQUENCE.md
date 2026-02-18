# Snapshot DataIntent v1 — Sequence (Architecture Lock)

This document is normative.
If code and this document diverge, code must be adjusted to match this document.

## 1) Snapshot Flow (ASCII)

```
User
  ↓
ChatViewModel
  ↓
QueryPipeline
  ↓
BackendQueryAPIService
  ↓
POST /query
  ↓
DataIntentRouter
  ↓
return data_intent
  ↓
QueryPipeline
  ↓
Domain Fetcher (calendar/reminders/photos/contacts/location/notes/files)
  ↓
Local formatter
  ↓
ChatViewModel
  ↓
UI render
```

## 2) Mail Branch (ASCII)

```
domain=mail
  ↓
QueryPipeline
  ↓
MailSyncService
  ↓
HelperAPIClient (/mail/*)
  ↓
Backend mail provider
  ↓
Return mail data
  ↓
Local formatter
```

## 3) Invariants (Must Hold)

1. Backend performs intent classification only.
2. Backend does not access system data.
3. Backend does not run analytics in v1.
4. `/query` never calls embeddings.
5. Snapshot engine never uses feature-store.
6. iOS contains no intent parsing logic.
7. Ambiguity is encoded as `domain="system"`.

## 4) Forbidden

- Analytics execution in `/query`.
- Source-gating fields (`analysis_ready`, `requires_sources`, `requirement_reason_codes`, `required_time_window`).
- Feature-store persistence.
- Retry loops in query pipeline.
- Embedding dependency for `/query`.
- Client-side intent parsing.

## 5) Deprecated

- `/assistant/feature-status` endpoint.
- Feature snapshot tables (e.g., `calendar_feature_events`).
- `analysis` payloads in `/query` responses.
