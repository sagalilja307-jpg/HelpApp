# Snapshot DataIntent v1 — regler för framtida utvecklare

Detta dokument är **normativt** för query-flödet i v1.
Om kod och dokumentation divergerar ska implementationen justeras så att reglerna nedan gäller.

## Syfte

Vi kör en avskalad arkitektur:

1. iOS skickar fråga till backend
2. Backend returnerar **enbart** `data_intent`
3. iOS hämtar data från rätt källa
4. iOS formaterar svaret lokalt

Ingen analytics-motor, ingen feature-store, ingen source-gating, inga retry-loopar.

## Icke-förhandlingsbara regler

- Intent-klassning ägs **endast** av backend.
- `POST /query` returnerar alltid formatet:
  - `{ "data_intent": { ... } }`
- iOS får inte göra egen intenttolkning (heuristik/interpreter).
- Retrieval-pipeline, embedding-service, mail-provider, assistant_store-ingest och auth ska lämnas orörda om inte en separat ändring kräver det.
- Analytics- och feature-store-signaler får inte återintroduceras i query-kontraktet.

## DataIntent v1-kontrakt

### Schema

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

### Ambiguitet

Ambigua frågor kodas alltid som:

```json
{
  "domain": "system",
  "operation": "needs_clarification",
  "filters": {
    "suggested_domains": ["calendar", "mail"]
  }
}
```

## Backend-regler

- Routerlogik ska ligga i `backend/src/helpershelp/application/query/data_intent_router.py`.
- Routerlogik ska vara deterministisk (regel/lexikon), inte analytics- eller embeddings-beroende.
- `/query` får inte köra retrieval, analytics eller readiness-kontroller.
- Bakåtkompatibel request för `/query` ska behållas:
  - `query|question`, `language`, `sources`, `days`, `data_filter`
- `/query` ska fungera även om embeddings är otillgängliga.

## iOS-regler

- `ios/Helper/Architecture/Pipeline/QueryPipeline.swift` ska:
  - anropa backend `/query`
  - routa på `data_intent.domain`
  - applicera `operation/timeframe/filters/sort/limit`
  - formatera svar lokalt
- Ingen lokal intentklassning får finnas kvar (`QueryInterpreter`, `QueryIntent`, heuristiska intent-checkar).
- Inga retry-loopar eller feature-readiness-checkar i query-flödet.
- Mail-frågor hämtas via befintliga backend mail-endpoints i mail-service.

## Ingest/feature-regler

- `POST /ingest` accepterar fortsatt `features` för kompatibilitet, men payloaden ignoreras.
- Feature-store-tabeller för analytics-snapshots ska inte användas eller återskapas.
- Endpointen `/assistant/feature-status` ska inte finnas i v1.

## Förbjudna signaler i query-svar

Följande fält får inte återintroduceras:

- `analysis_ready`
- `requires_sources`
- `requirement_reason_codes`
- `required_time_window`

## Ändringspolicy för v1

Vid utökning av DataIntent:

1. Lägg till/ändra enum i backend-modeller och routerregler.
2. Uppdatera iOS DTO + query-routering för exakt samma kontrakt.
3. Dokumentera ny domän/operation/filter i detta dokument.
4. Lägg till tester (backend + iOS) innan merge.

Ingen v1-ändring får återinföra analytics-lager eller feature-persistens.

## Verifieringschecklista (måste passera före merge)

- `/query` returnerar alltid ett giltigt `data_intent`-objekt.
- Inga körbara kodvägar till analytics-service eller feature-status endpoint.
- Retrieval-tester passerar oförändrade.
- iOS-queryflödet kör utan intent-interpreter, retry-loopar och feature-gating.

Snabb reachability-kontroll:

```bash
rg "analysis_service|feature-status|requires_sources|analysis_ready|requirement_reason_codes|required_time_window" backend ios
```
