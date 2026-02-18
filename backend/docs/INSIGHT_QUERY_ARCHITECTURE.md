# Snapshot DataIntent Architecture (v1)

This document is normative.
All clients and servers MUST comply with this model.
Violations require explicit architectural review.

## Purpose

Denna modell beskriver hur en fråga blir ett DataIntent och sedan besvaras lokalt i iOS.
Ingen analytics-motor, ingen feature-store, ingen source-gating och inga retry-loopar.

## System Model

1. iOS skickar `POST /query`.
2. Backend returnerar **endast** `data_intent`.
3. iOS hämtar data från rätt källa.
4. iOS formaterar svaret lokalt.

All dataåtkomst är:
- användardriven
- kontextbaserad
- begränsad till explicit timeframe

## Query Lifecycle

1. iOS skickar `POST /query`.
2. Backend:
   - klassar `domain`
   - sätter `operation`
   - resolver `timeframe` och `filters`
3. Backend svarar:
   - `{ "data_intent": { ... } }`
4. iOS:
   - routar till rätt källa
   - hämtar data
   - applicerar `operation/timeframe/filters/sort/limit`
   - formaterar svar

## Responsibilities

- Backend är source-of-truth för intent-klassning och kontrakt.
- iOS är source-of-truth för lokal systemdata.
- Inga analytics- eller feature-store-paths i v1.

## Design Principles

- Deterministisk router (regel/lexikon), inga embeddings.
- `/query` är alltid tillgängligt och ska inte bero på embeddings.
- iOS gör ingen intenttolkning och inga retry-loopar.

## Forbidden Patterns

Följande är explicit förbjudna i v1:

- Source gating eller readiness-signaler.
- Feature-store persistence.
- Analytics calculators.
- Client-side intent parsing.
- Auto-retry-loops i query-flödet.

## Reference

Normativt kontrakt och regler:
- `docs/architecture/SNAPSHOT_DATAINTENT_V1_REGLER.md`
