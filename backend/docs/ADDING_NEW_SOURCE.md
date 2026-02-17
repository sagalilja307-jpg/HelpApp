# Adding a New Insight Source

## Purpose

Detta dokument ar den normativa mallen for att lagga till en ny insight-kalla utan arkitekturdrift.

## Required Layers

Varje ny kalla maste implementera alla lager nedan.

### 1) Backend

#### a) Reason codes

Definiera maskinlasbara reason codes:
- `<source>_data_missing`
- `<source>_data_stale`
- `<source>_coverage_gap`

Exempel:
- `reminder_data_missing`
- `reminder_data_stale`
- `reminder_coverage_gap`

#### b) Feature-store table

Skapa egen feature-tabell (eller definiera generisk snapshot-tabell med samma semantik).

Exempel:
- `reminder_feature_events`

Krav:
- stabilt snapshot-id
- `snapshot_hash`
- `updated_at`
- coverage-falt for status-berakning

#### c) Analytics calculators

Kalkylatorer far endast lasa fran feature-store.

Forbjudet:
- lasa analytics-data direkt fran `unified_items`
- bero pa embeddings i analytics-path

### 2) iOS

#### a) FeatureBuilder

Skapa en builder for kallan.

Exempel:
- `ReminderFeatureBuilder`

Krav:
- input ar explicit `DateInterval` (`required_time_window`)
- returnerar stabila IDs
- beraknar `snapshot_hash`
- ingen global/full sync

#### b) Pipeline integration

`QueryPipeline` maste:
1. lasa `requires_sources`
2. hamta feature-status vid behov
3. bygga + ingest features
4. retrya exakt en gang

### 3) Documentation

For varje ny kalla maste dokumentationen innehalla:
- permission model
- retention policy
- approximationer/antaganden
- `limitations` som exponeras i `analysis`

## Architecture Invariants

1. Alla kallor använder samma source-gating-kontrakt.
2. Alla kallor använder `required_time_window`.
3. Alla kallor returnerar `limitations` nar coverage ar bristfallig.
4. Inga kallor triggar bakgrundssync utan användarinitierad fraga.
5. Ingen kalla bypassar dispatcher.

## Checklist

Anvand denna checklista innan en ny kalla anses klar:

- [ ] Reason codes tillagda
- [ ] Feature-table + index + upsert regler klara
- [ ] `GET /assistant/feature-status` utokad for kallan
- [ ] `POST /ingest` stoder source features bakatkompatibelt
- [ ] Analytics calculators laser endast feature-store
- [ ] iOS FeatureBuilder klar for explicit tidsfonster
- [ ] QueryPipeline auto-retry max 1 verifierad
- [ ] Regression tester grona (retrieval + analytics + kontrakt)
- [ ] Docs uppdaterade
