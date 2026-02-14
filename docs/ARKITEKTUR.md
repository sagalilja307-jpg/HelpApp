# Helper System Arkitektur

## Hur delarna pratar med varandra

Repo-paths

* iOS-projekt: `ios/Helper.xcodeproj`
* Backend: `backend/`
* Arkitektur-dokument: `docs/ARKITEKTUR.md`

---

# 🗂 Mappstruktur (iOS)

```
Helper/
├── Architecture/              ← Arkitektur & Koordinering
│   ├── Coordinators/          (MemoryCoordinator, IndexingCoordinator, QueryDataCoordinator, DecisionCoordinator, SafetyCoordinator)
│   └── Pipeline/              (QueryPipeline, QueryInterpreter, QueryAnswerComposer)
│
├── Core/                      ← Business Logic
│   ├── LLM/                   (LLMClient, LLMIntent, TextEmbedding, LLMAvailability)
│   ├── Safety/                (SafetyDecisionEngine, SafetyPolicy)
│   ├── Decision/              (DecisionEngine, DecisionPipeline)
│   └── Query/                 (QuerySourceAccess, QueryModels)
│
├── Services/                  ← Infrastructure & Integration
│   ├── Memory/                (MemoryService, NotesStoreService)
│   ├── Indexing/              (ContactsCollectorService, PhotosIndexService, FilesImportService, LocationCollectorService, LocationSnapshotService)
│   ├── Backend/               (AssistantIngestService, BackendQueryService, SupportSettingsService)
│   ├── System/                (PermissionManager)
│   ├── Sharing/               (ShareImportService, SourceConnectionStore)
│   ├── FollowUp/              (FollowUpManager, FollowUpEvaluator, FollowUpPolicy)
│   ├── Reminders/             (ReminderSyncManager)
│
├── Data/                      ← Models & Utilities
│   ├── Models/
│   ├── Helpers/
│   └── MailManagerUpdated/
│
├── Features/                  ← UI Layer
│   ├── Chat/
│   ├── Settings/
│   └── Onboarding/
│
├── AppShell/
│   ├── HelperApp.swift
│   └── AppIntegrationConfig.swift
│
├── Shared/
├── Minne/                     ← Legacy
└── Resources/
```

---

# 🧱 ÖVERGRIPANDE ARKITEKTUR

```
App Layer (SwiftUI)
        ↓
Coordinators (@MainActor)
        ↓
MemoryService
        ↓
ModelContext (per operation)
        ↓
Services (context passed as parameter)
```

Viktig regel:

> ModelContext skapas per operation och lagras aldrig.

---

# 🏛 Coordinator-Driven Architecture (Swift 6-kompatibel)

## Roller

### App Layer

* Skapar MemoryService
* Skapar Coordinators
* Skickar coordinators till views
* Äger ingen ModelContext

---

### Coordinators (`@MainActor`)

* Äger MemoryService
* Skapar `ModelContext` per metod
* Anropar services
* Låter context dö efter operation

Exempel:

```swift
@MainActor
final class MemoryCoordinator {

    private let memoryService: MemoryService
    private let notesStore = NotesStoreService()

    init(memoryService: MemoryService) {
        self.memoryService = memoryService
    }

    func createNote(title: String, body: String) throws {
        let context = memoryService.context()
        try notesStore.createNote(title: title, body: body, in: context)
    }
}
```

---

### Services

* Får `ModelContext` som parameter
* Sparar aldrig context
* Sparar aldrig MemoryService
* Är inte actors
* Är inte `@MainActor`

Exempel:

```swift
struct NotesStoreService {

    func createNote(
        title: String,
        body: String,
        in context: ModelContext
    ) throws {

        let note = UserNote(...)
        context.insert(note)
        try context.save()
    }
}
```

---

# 🔐 Arkitekturregler (Swift 6)

✅ Services tar ALDRIG `MemoryService` i init
✅ Services lagrar ALDRIG `ModelContext`
✅ Services får `in context: ModelContext` per method call
✅ Coordinators är `@MainActor`
✅ Coordinators äger context lifecycle
✅ En ModelContext per operation
✅ ModelContext lämnar aldrig isolation-boundary

---

# 🧠 Stabilitetslager (v1)

Backend är source-of-truth för support policies.

* `assistant.support.level` (0..3)
* `assistant.support.paused`
* `assistant.support.adaptation_enabled`
* Daglig nudging cap: 0 / 2 / 3 / 5
* 24h fallback-fönster

iOS:

* Visar settings sheet
* Uppdaterar backend via API
* Visar lärda mönster
* Kan återställa vikter

---

# 🧩 DEL 1 — Innehållsanalys (iOS)

```
User Input
    ↓
ContentClassifier
    ↓
IntentType (.note, .calendar, .none ...)
    ↓
DecisionEngine
```

Ingen backend involverad ännu.

---

# 🧩 DEL 2 — Beslutssystem (iOS)

```
Intent
    ↓
DecisionEngine
    ↓
DecisionAction (show / suppress / schedule / none)
    ↓
DecisionCoordinator
    ↓
MemoryService.appendDecision(in: context)
```

All loggning är append-only.

---

# 🧩 DEL 3 — QueryPipeline (iOS ↔ Backend)

Flöde:

1. `POST /llm/interpret-query`
2. Backend klassificerar intent + topic
3. iOS väljer källor
4. `POST /llm/similarity-batch`
5. Backend rankar
6. `POST /llm/formulate-items`
7. Backend formulerar
8. iOS visar svar
9. iOS loggar beslut

Backend är:

* Stateless
* Rankar
* Formulerar
* Embed:ar
* Men fattar inga användarbeslut

---

# 🧠 DEL 4 — Minneshantering (iOS Only)

```
App → Coordinator
       ↓
memoryService.context()
       ↓
ServiceMethod(in: context)
       ↓
context.save()
       ↓
Context dör
```

Ingen context delas.
Ingen context lagras.

---

# 🔌 API-ENDPOINTS (Backend)

LLM:

* /llm/interpret-query
* /llm/embed
* /llm/similarity-batch
* /llm/formulate-items

Mail:

* /mail/unanswered
* /mail/recent
* /mail/from-domain

Support:

* /settings/support
* /settings/learning
* /settings/learning/reset

Auth:

* /auth/validate
* /auth/refresh

---

# 🔒 Säkerhetsgränser

Backend gör:

✅ Embedding
✅ Ranking
✅ Formulering
✅ Retrieval

Backend gör INTE:

❌ Beslutslogik
❌ Lagra user data
❌ Se historik
❌ Fatta policybeslut

iOS gör:

✅ Beslut
✅ Policy
✅ Lokal lagring
✅ Datakällval
✅ All context-lifecycle

---

# 🎯 Viktigaste Arkitekturprincipen

> Coordinator äger livscykeln.
> Service gör arbetet.
> Context lever och dör inom samma funktion.

---


