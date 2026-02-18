# Snapshot DataIntent v1 — Efterdokumentation

**Datum:** 2026-02-18  
**Scope:** Hela monorepot (`ios/` + `backend/`)

## Målbild (uppnådd)

Query-kedjan är nu minimal och deterministisk:

`ChatView -> QueryPipeline -> Backend /query -> DataIntentRouter -> DataIntent -> iOS domain fetcher -> formatter -> ChatView`

Inga analytics/source-gating-shims i query-flödet.  
Inga backend-`/llm/*` endpoints.  
Ingen iOS snapshot-ingest i query-kedjan.

## Genomförda förändringar

1. Backend `/llm/*` och embedding/retrieval-stack borttagen.
2. Backend `/ingest` kontrakt rensat: legacy `features` accepteras inte längre (422 vid payload med `features`).
3. Backend tids-/datumlogik konsoliderad till central resolver/service och tydlig granularity (`day|week|month|custom`).
4. iOS query-kedja rensad från legacy-komponenter (intenttolkning/feature-status/snapshot-ingest).
5. `Etapp2IngestCheckpoint` borttagen med explicit migration-plan.
6. iOS central `DateService` införd och applicerad över modellen/services.
7. Dödkod + legacy docs rensade (inklusive kvarvarande analytics/source-gating artefakter).

## Commit-spårbarhet

1. `0bf572c` test: stabilize iOS baseline against current APIs
2. `ab72cb2` refactor: remove llm and retrieval stack from backend
3. `0d36baf` refactor: centralize backend timeframe and time parsing
4. `4bf0a1c` refactor: remove legacy features from ingest contract
5. `53b3b98` refactor: remove iOS legacy query ingest placeholders
6. `2bbbcfb` refactor: remove checkpoint store and add schema migration plan
7. `6f5155a` refactor: centralize iOS date and time handling
8. `5f18186` chore: purge legacy query docs and dead analytics artifacts

## Verifiering

### Backend

- `pytest -q` passerar.
- `/query` returnerar `data_intent`.
- `/llm/*` existerar inte.
- `/ingest` med `features` ger valideringsfel (`422`).

### iOS

- `xcodebuild ... test` passerar (Helper scheme, iPhone 17 simulator).
- QueryPipeline kör backend-driven DataIntent v1 utan lokal intenttolkning.

### Invarians-grep (slutkontroll)

Noll träffar för:

- Backend: `analysis_ready|requires_sources|required_time_window|feature-status|QueryOrchestrator|analysis_service`
- iOS: `QueryIntent|QueryInterpretation|FeatureStatus|CalendarFeatureBuilder|AssistantIngest|Etapp2IngestCheckpoint`
- API-routes: `/llm`-routeexponering

## Kända rester (ej query-call-path)

- Historiska referenser kan finnas i icke-canonical dokument och historiska säkerhetsrapporter.
- De påverkar inte runtime-path eller API-kontrakt.

## Canonical källor framåt

- `docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md`
- `docs/architecture/SNAPSHOT_DATAINTENT_V1.md`
- `docs/architecture/SNAPSHOT_DATAINTENT_V1_SEQUENCE.md`
- `backend/README.md`
- `backend/docs/STRUCTURE.md`
