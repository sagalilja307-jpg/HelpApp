# Insight Query Architecture (v1)

## Purpose

Detta dokument beskriver den mentala modellen for hur en fraga blir analys i ett Apple-kompatibelt system.

## System Model

Helper använder en tvåstegsmodell for analysfrågor:

1. Backend tolkar frågan och avgor vilka datakallor som behovs.
2. iOS hamtar och beraknar feature-snapshots on-demand (user-driven).
3. Backend analyserar snapshots deterministiskt.
4. LLM formulerar svar endast fran strukturerad analysdata.

Ingen automatisk massiv bakgrundssync av systemdata sker.

All dataatkomst ar:
- användardriven
- kontextbaserad
- begränsad till begärt tidsfönster

## Query Lifecycle

1. iOS skickar `POST /query`.
2. Backend:
   - tolkar intent
   - beraknar `required_time_window`
   - avgor om feature-data ar tillracklig
3. Om data saknas eller ar stale returnerar backend:
   - `analysis_ready=false`
   - `requires_sources=["calendar"]`
   - `requirement_reason_codes` med orsak
4. iOS:
   - hamtar endast begart tidsfonster
   - bygger snapshots
   - skickar `POST /ingest` med `features`
   - gor exakt en retry av `POST /query`
5. Backend:
   - kor analytics deterministiskt
   - returnerar `analysis_ready=true`

Loopskydd: max 1 retry per användarfraga.

## Responsibilities

- Backend ar source-of-truth for intent, readiness och required sources.
- iOS ar source-of-truth for lokal systemdata (EventKit, etc.).
- Dispatcher ar enda routningslager mellan analytics-path och retrieval-path.

## Design Principles

- Backend ar source-of-truth for intent.
- iOS ar source-of-truth for systemdata.
- Ingen duplicerad intent-parser i iOS.
- Ingen automatisk full sync av systemappar.
- Snapshots ar idempotenta.
- Max 1 retry per fraga.
- Analytics använder aldrig embeddings.
- Retrieval använder embeddings och kan returnera `503`.

## Architecture Invariants

1. Alla kallor använder samma source-gating-kontrakt.
2. Alla kallor använder `required_time_window`.
3. Alla kallor returnerar `limitations` nar coverage ar bristfallig.
4. Inga kallor triggar bakgrundssync utan användarinitierad fraga.
5. Ingen kalla bypassar dispatcher.
