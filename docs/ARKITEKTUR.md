# Helper System Arkitektur - Hur Delarna Pratar

## Repo-paths
- iOS-projekt: `ios/Helper.xcodeproj`
- Backend: `backend/`
- Arkitektur-dokument: `docs/ARKITEKTUR.md`

## Överblick
```
┌─────────────────────────────────────────────────────────────┐
│                    iOS APP (Helper)                          │
│  ContentAnalysis → DecisionEngine → QueryPipeline → Memory   │
└─────────────┬───────────────────────────────────────────────┘
              │
              │ HTTP/JSON
              │
┌─────────────▼───────────────────────────────────────────────┐
│            BACKEND (HelpersHelp)                             │
│  LLM ← → MailSource ← → RetrievalCoordinator ← → API         │
└─────────────────────────────────────────────────────────────┘
```

---

## Stabilitetslager (v1)

Helper använder ett explicit stabilitetslager där backend är source-of-truth:
- `assistant.support.level` (`0..3`) styr interventionsgrad.
- `assistant.support.paused` pausar interventioner utan att ändra nivå.
- `assistant.support.adaptation_enabled` tillåter adaptation inom vald nivå.
- Daglig nudgetak per nivå: `0/2/3/5`.
- Tidskritisk fallback visas med 24h-fönster även vid låg intensitet.

I iOS finns en settings-sheet i `ChatView` (toolbar) som:
- ändrar stödnivå,
- pausar/återupptar adaptation,
- visar lärda mönster och ändringsorsaker,
- återställer enbart lärda vikter.

---

## DEL 1️⃣: INNEHÅLLSANALYS (iOS)
### ContentAnalysis → Rest of system

```
Användare skriver något
        ↓
[ContentClassifier]
        ↓
Bestämmer typ: .sendMessage, .calendar, .reminder, .note, .none
        ↓
Skickas till DecisionEngine
```

**Indata:** Naturlig text från användare
**Utdata:** IntentType enum (klassificering)
**Kontakt:** Internt i iOS - ingen backend-anrop ännu

---

## DEL 2️⃣: BESLUTSSYSTEM (iOS)
### DecisionEngine → QueryPipeline eller MemoryService

```
[Klassificerad innehål]
        ↓
[DecisionEngine]
  - Värderar förslagets relevans
  - Kontrollerar policies (supportive mode, nudges osv)
  - Loggar beslut i append-only log
        ↓
Beslut: "show suggestion" / "suppress" / "schedule" / "none"
        ↓
Om "show" → Skickas till QueryPipeline
Om lagring → Skickas till MemoryService
```

**Indata:** ActionSuggestion (vad systemet vill göra)
**Utdata:** DecisionAction (What to do)
**Kontakt:** Internt i iOS

---

## DEL 3️⃣: FRÅGEPIPELINE (iOS) ↔ BACKEND
### iOS QueryPipeline → Backend /llm/* endpoints

```
┌─ iOS APP ──────────────────────────────────┐
│ [UserQuery]                                │
│  "Vad är min försäkringstatus?"           │
│         ↓                                  │
│ [QueryInterpreter]                        │
│  Förberedelser för frågans                │
│         ↓                                  │
│ POST /llm/interpret-query                 │
│ {                                         │
│   "query": "Vad är min försäkringstatus?" │
│   "language": "sv"                        │
│ }                                         │
└─────────┬────────────────────────────────┘
          │
          │ HTTP POST
          │
┌─────────▼────────────────────────────────────────┐
│ Backend: API Layer                               │
│                                                  │
│ query_service.interpret_query()                  │
│   ↓                                              │
│ [LLMService - QueryInterpretationService]        │
│   - BGE-M3 embedding av query                   │
│   - Similarity mot INTENT_LABELS                │
│   - Similarity mot TOPIC_LABELS                 │
│   - Applicerar INTENT_THRESHOLD (0.75)          │
│   - Applicerar TOPIC_THRESHOLD (0.7)            │
│                                                  │
│ Returnerar:                                      │
│ {                                               │
│   "intent": "status",                          │
│   "topic": "försäkring",                       │
│   "confidence": 0.82,                          │
│   "sources": ["email", "memory"]               │
│ }                                               │
└─────────┬────────────────────────────────────┘
          │
          │ JSON Response
          │
┌─────────▼──────────────────────────────────┐
│ iOS QueryPipeline                          │
│         ↓                                  │
│ [QueryDataFetcher]                        │
│  - Bestämmer vad som behöver hämtas      │
│  - Kilder: calendar, reminders, memory   │
│         ↓                                  │
│ POST /retrieval/fetch                    │ (Framtida)
│ {                                        │
│   "intent": "status",                   │
│   "topic": "försäkring",                │
│   "sources": ["memory", "email"],       │
│   "timeRange": {"days": 90}             │
│ }                                        │
└─────────┬──────────────────────────────┘
          │
          │ HTTP POST
          │
┌─────────▼────────────────────────────────────┐
│ Backend: RetrievalCoordinator                │
│                                              │
│ [retrieval_coordinator.run()]                │
│   ↓                                          │
│ För varje källa:                            │
│  - MailSource.fetch() → E-post              │
│  - MemoryService.fetch() → Sparade minnen  │
│   ↓                                          │
│ [RetrievalCoordinator]                      │
│   - Samlar alla kandidater                 │
│   - BGE-M3 embedding av varje kandidat    │
│   - Räknar similarity till query           │
│   - Sorterar efter relevans                │
│   - Applicerar max_per_source limits:      │
│     * email: 6                             │
│     * memory: 4                            │
│     * signal: 2                            │
│   - Total max: 12 items                    │
│   ↓                                        │
│ Returnerar topranked ContentObjects       │
└─────────┬────────────────────────────────┘
          │
          │ JSON (ContentObjects)
          │
┌─────────▼──────────────────────────────────┐
│ iOS QueryPipeline                          │
│         ↓                                  │
│ [QueryAnswerComposer]                     │
│  - Tar rankat data                       │
│  - Formaterar för visning                │
│  - Sparar i QueryResult                  │
│         ↓                                  │
│ POST /llm/formulate-items                │
│ {                                        │
│   "items": [                             │
│     {                                    │
│       "id": "email_123",                │
│       "source": "email",                │
│       "subject": "Försäkring update",   │
│       "body": "Vi behöver..."           │
│     }                                    │
│   ],                                     │
│   "intent": "SUMMARY",                  │
│   "language": "sv"                       │
│ }                                        │
└─────────┬───────────────────────────────┘
          │
          │ HTTP POST
          │
┌─────────▼────────────────────────────────────┐
│ Backend: LLM Layer                           │
│                                              │
│ [text_generation_service.formulate()]       │
│   ↓                                         │
│ GPT-SWE3:                                   │
│  - Tar exakt de items som gavs            │
│  - Formulerar på svenska                  │
│  - Lägger INTE till ny info               │
│  - Respekterar intent (SUMMARY, osv)      │
│  - Skriver naturlig text                  │
│   ↓                                        │
│ Returnerar:                                │
│ {                                         │
│   "text": "Din försäkringsstatus är...", │
│   "items_used": 5,                       │
│   "language": "sv"                       │
│ }                                         │
└─────────┬───────────────────────────────┘
          │
          │ JSON Response
          │
┌─────────▼────────────────────────────────┐
│ iOS App - Visar resultatet                │
│ "Din försäkringsstatus är..."            │
└──────────────────────────────────────────┘
```

---

## DEL 4️⃣: MINNESHANTERING (iOS ↔ Backend)
### MemoryService (iOS) ← → Backend API

```
Systemet vill spara något (mail, beslut, pattern)
        ↓
[MemoryService] (iOS-lokal SwiftData)
  - putRawEvent() → Lagrar e-post/event
  - appendDecision() → Append-only logs
  - upsertBehaviorPattern() → Mönster
  - proposeCluster() → Grupperar data
        ↓
Sparas lokalt + möjligtvis sync till backend
```

**Indata:** ContentObject, Decision, BehaviorPattern
**Utdata:** Persisterad data
**Kontakt:** Mestadels lokal, framtida backend-sync

---

## API ENDPOINTS - KOMPLETT LISTA

### 🧠 LLM Endpoints (Backend)

| Endpoint | Method | Från | Till | Syfte |
|----------|--------|------|------|-------|
| `/llm/interpret-query` | POST | QueryInterpreter | QueryInterpretationService | Klassificera intent + topic |
| `/llm/embed` | POST | QueryDataFetcher | EmbeddingService | Embed en text |
| `/llm/embed-batch` | POST | RetrievalCoordinator | EmbeddingService | Embed flera texter |
| `/llm/similarity` | POST | RetrievalCoordinator | EmbeddingService | Räkna similarity mellan två texts |
| `/llm/similarity-batch` | POST | RetrievalCoordinator | EmbeddingService | Rank många texts mot query |
| `/llm/formulate-items` | POST | QueryAnswerComposer | TextGenerationService | Omformulera items till naturlig text |

### 📧 Mail Endpoints (Backend)

| Endpoint | Method | Från | Syfte |
|----------|--------|------|-------|
| `/mail/unanswered` | GET | RetrievalCoordinator | Hämta obesverade mejl |
| `/mail/recent` | GET | RetrievalCoordinator | Hämta senaste mejl |
| `/mail/from-domain` | GET | RetrievalCoordinator | Sök mejl från domän |

### 🔐 Auth Endpoints

| Endpoint | Method | Syfte |
|----------|--------|-------|
| `/auth/validate` | POST | Validera token |
| `/auth/refresh` | POST | Uppdatera token |
| `/auth/store` | POST | Spara token i backend-store |

### 🛟 Support/learning Endpoints

| Endpoint | Method | Syfte |
|----------|--------|-------|
| `/settings/support` | GET | Hämta stödnivå, caps och effektiv policy |
| `/settings/support` | POST | Uppdatera `support_level`, `paused`, `adaptation_enabled` |
| `/settings/learning` | GET | Visa lärda mönster + auditorsaker |
| `/settings/learning/pause` | POST | Pausa/återuppta adaptation |
| `/settings/learning/reset` | POST | Nollställ lärda vikter (inte stödnivå) |

---

## DATA FLOW SAMMANDRAG

### Request → Response Cykel

```
1. [iOS] Användare frågar något
   └─→ ContentAnalysis klassificerar
   
2. [iOS] DecisionEngine värderar
   └─→ Bestämmer om QueryPipeline ska köras
   
3. [iOS] QueryPipeline.interpret()
   └─→ POST /llm/interpret-query
   
4. [Backend] LLM klassificerar
   └─→ Returnerar intent + topic
   
5. [iOS] QueryDataFetcher bestämmer sources
   └─→ Hämtar från calendar, reminders, memory, osv
   
6. [Backend] RetrievalCoordinator rankar
   └─→ BGE-M3 embeddings + similarity scoring
   
7. [iOS] QueryAnswerComposer prepares items
   └─→ POST /llm/formulate-items
   
8. [Backend] LLM formulerar
   └─→ GPT-SWE3 omskriver
   
9. [iOS] Visar resultat
   └─→ QueryResult presenteras
   
10. [iOS] MemoryService sparar
    └─→ Append-only decision log
```

---

## KRITISKA GRÄNSER

### iOS → Backend
- **LLM-anrop minimal**: Bara när QueryPipeline är aktivt
- **Offline-först**: iOS fungerar utan backend
- **Privacy**: All data enkrypterad vid överföring

### Backend → iOS
- **Stateless**: Backenden är inte ansvarig för context
- **Rankad data**: Returnerar alltid ranked candidates, ej beslut
- **Formulation only**: GPT-SWE3 omformulerar aldrig omöjligheter

---

## EXEMPEL: Fullständig Convo

```
Användare:  "Vad hände med min försäkringsskada?"

iOS QueryPipeline:
  POST /llm/interpret-query
  {
    "query": "Vad hände med min försäkringsskada?",
    "language": "sv"
  }

Backend:
  → BGE-M3 embedding
  → Compare mot: "summary", "status", "question"
  → Confidence för "status": 0.88 ✓
  → Topic "försäkring": 0.92 ✓
  ← {intent: "status", topic: "försäkring", ...}

iOS RetrievalCoordinator:
  Hämtar:
  - Email från "försäkring" domain (6 max)
  - Memory entries om "försäkring" (4 max)
  
  POST /llm/similarity-batch
  {
    "query": "försäkringsskada",
    "candidates": [email1, email2, memory1, ...]
  }

Backend:
  → BGE-M3 rank alla
  ← Top 10 ranked items

iOS QueryAnswerComposer:
  POST /llm/formulate-items
  {
    "items": [
      {email_123: "Försäkringskada ref #1234..."},
      {memory_45: "Skickade in underlag 2026-01..."},
      ...
    ],
    "intent": "STATUS"
  }

Backend:
  → GPT-SWE3 skriver
  ← "Din försäkringsskada #1234 är nu under granskning..."

iOS:
  Visar resultat + Sparar i DecisionLog
```

---

## SÄKERHET & GRÄNSER

### Vad Backend GÖR
✅ Klassificera intent/topic  
✅ Embed text (BGE-M3)  
✅ Rank candidates (similarity)  
✅ Formulera redan-vald data (GPT-SWE3)  

### Vad Backend GÖR INTE
❌ Bestämma vilken data som är viktigast  
❌ Lägga till ny information  
❌ Lagra user data (allt lokalt på iOS)  
❌ Se user history (stateless)  
❌ Döma lämpliga beslut  

### Vad iOS GÖR
✅ Klassificera innehål lokalt  
✅ Värderar förslag mot policies  
✅ Väljer vilka källor att söka  
✅ Lagrar all data lokalt  
✅ Fattar alla användarrelaterade beslut  

### Vad iOS GÖR INTE
❌ Embed text (backend gör det)  
❌ Formulera (GPT-SWE3 gör det)  
❌ Rank items (BGE-M3 gör det)
