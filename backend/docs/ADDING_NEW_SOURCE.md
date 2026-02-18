# Adding a New Snapshot Source (DataIntent v1)

This document is normative.
All new sources MUST comply with these rules.
Violations require explicit architectural review.

## Purpose

Denna guide beskriver hur du lägger till en ny källa i Snapshot DataIntent v1
utan att återinföra analytics, feature-store, source-gating eller retry-loopar.

## Required Layers

Varje ny källa MUST implementera alla lager nedan.

### 1) Backend

#### a) DataIntent-kontrakt

- Lägg till domänen i `DataIntent.domain` enum.
- Definiera giltiga `operation` för domänen.
- Uppdatera `DataIntentRouter` med domännyckelord och minimala filter/sort-regler.

Filer:
- `backend/src/helpershelp/api/models.py`
- `backend/src/helpershelp/application/query/data_intent_router.py`

#### b) Router-regler

- Routern ska vara deterministisk (lexikon/regelbaserad).
- Routern får inte bero på embeddings eller analytics.
- Routern får inte trigga retrieval eller andra backends.

#### c) Testkrav

- Lägg till/uppdatera tester för:
  - domänklassning
  - operation-klassning
  - timeframe/filters/sort/limit
  - ambiguity (`system/needs_clarification`)

### 2) iOS

#### a) QueryPipeline routing

- Mappa `data_intent.domain` till rätt lokal fetcher.
- Applicera `operation/timeframe/filters/sort/limit` lokalt.
- Inga lokala intent-heuristiker.

#### b) Mail

- Mail ska hämtas via backend mail-endpoints (ingen ny iOS-mail-arkitektur).

### 3) Documentation

- Uppdatera `docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md` med:
  - ny domän
  - operationer
  - filter-nycklar
  - sort/limit-regler
- Uppdatera `backend/docs/STRUCTURE.md` om struktur ändras.

## Architecture Invariants

1. Intent-klassning är backend-only.
2. Ingen analytics/feature-store/source-gating i v1.
3. `/query` returnerar alltid `{ "data_intent": { ... } }`.
4. iOS gör ingen intenttolkning och inga retry-loopar.

## Example Checklist

- [ ] `DataIntent` enum uppdaterad
- [ ] `DataIntentRouter` regler uppdaterade
- [ ] iOS `QueryPipeline` mappar domän + operation
- [ ] Tester uppdaterade (backend + iOS)
- [ ] Dokumentation uppdaterad
