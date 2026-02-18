# Source Gating Contract (Deprecated)

This document is deprecated.
Source gating was removed in Snapshot DataIntent v1.
Do not reintroduce these signals without explicit architectural review.

## Current v1 Behavior

- `POST /query` returns `{ "data_intent": { ... } }` only.
- `/assistant/feature-status` does not exist.
- `POST /ingest` accepts `features` for backward compatibility but ignores it.

## Deprecated Fields (must not return)

- `analysis_ready`
- `requires_sources`
- `requirement_reason_codes`
- `required_time_window`

## Reference

Normativ v1 contract:
- `docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md`
