**Architecture Sanitation PR Template**

Purpose: present each detected violation with a minimal proposed change, rationale and severity.

Instructions for reviewer:
- Review each violation and its proposed fix.
- Mark approvals or request changes per item.
- For non-trivial items (architectural discussion), leave a comment and do not auto-apply.

---
Project: HelpersHelp
Author: automated-report
Generated: (auto)

Summary:
 Imports: helpershelp.infrastructure.persistence.sqlite_storage

- `Mechanical`: trivial rename of import to new path (safe to patch automatically after review)
- `Design`: requires architectural discussion; do not auto-apply
- `High`: API-layer importing low-level infra; requires careful fix


Violations (proposed fixes)

1) Violation
From: helpershelp.api.app
Imports: helpershelp.assistant.sync
File: src/helpershelp/api/app.py
Proposed Fix: import from `helpershelp.application.assistant.sync` or move sync start into an application-level facade. Prefer: `from helpershelp.application.assistant.sync import start_sync_loop`.
Category: Mechanical / Low-risk
Rationale: sync functionality belongs to the application layer; API should call application entrypoint.

2) Violation
From: helpershelp.api.deps
Imports: helpershelp.mail.provider
File: src/helpershelp/api/deps.py
Proposed Fix: use the mail port interface `helpershelp.ports.mail_port` and inject concrete provider via DI. Example: accept `mail_provider` from app startup rather than importing legacy provider.
Category: Design
Rationale: API layer should depend on ports, not concrete mail implementation.

3) Violation
From: helpershelp.api.routes.assistant
Imports: helpershelp.assistant.language_guardrails
File: src/helpershelp/api/routes/assistant.py
Proposed Fix: import a stable application API, e.g. `helpershelp.application.assistant.language_guardrails` (move enforcement to application) or expose a minimal facade under `helpershelp.application.assistant`.
Category: Mechanical / Review
Rationale: keep assistant internals behind application boundary.

4) Violation
From: helpershelp.api.routes.assistant
Imports: helpershelp.assistant.models
File: src/helpershelp/api/routes/assistant.py
Proposed Fix: import models from `helpershelp.domain.models`.
Category: Mechanical
Rationale: domain models are the canonical source for shared types.

5) Violation
From: helpershelp.api.routes.assistant
Imports: helpershelp.application.assistant.proposals
File: src/helpershelp/api/routes/assistant.py
Proposed Fix: import from `helpershelp.application.assistant.proposals` (use application-level API).
Category: Mechanical
Rationale: proposals are application logic, surface via application package.

6) Violation
From: helpershelp.api.routes.assistant
Imports: helpershelp.domain.rules.scoring
File: src/helpershelp/api/routes/assistant.py
Proposed Fix: import from `helpershelp.domain.rules.scoring`.
Category: Mechanical
Rationale: scoring rules live in domain.rules.

7) Violation
From: helpershelp.api.routes.assistant
Imports: helpershelp.assistant.support
File: src/helpershelp/api/routes/assistant.py
Proposed Fix: import from `helpershelp.application.assistant.support`.
Category: Mechanical
Rationale: support policy resolution is application-level.

8) Violation
From: helpershelp.api.routes.assistant
Imports: helpershelp.domain.value_objects.time_utils
File: src/helpershelp/api/routes/assistant.py
Proposed Fix: import from `helpershelp.domain.value_objects.time_utils`.
Category: Mechanical
Rationale: time utilities belong to domain value objects.

9) Violation
From: helpershelp.api.routes.auth
Imports: helpershelp.infrastructure.security.token_manager
File: src/helpershelp/api/routes/auth.py
Proposed Fix: use `helpershelp.infrastructure.security.token_manager` or an application facade for token storage (avoid direct assistant.tokens import).
Category: Mechanical / Review
Rationale: tokens are an infra concern; API should use application/infra facade.

10) Violation
From: helpershelp.api.routes.auth
Imports: helpershelp.mail.oauth_models
File: src/helpershelp/api/routes/auth.py
Proposed Fix: move/consume OAuth types from `helpershelp.application.mail` or `helpershelp.domain.models` and avoid importing mail internals directly.
Category: Design
Rationale: OAuth models are cross-cutting; decide canonical package first.

11) Violation
From: helpershelp.api.routes.health
Imports: helpershelp.domain.value_objects.time_utils
File: src/helpershelp/api/routes/health.py
Proposed Fix: import `helpershelp.domain.value_objects.time_utils`.
Category: Mechanical

12) Violation
From: helpershelp.api.routes.llm
Imports: helpershelp.domain.value_objects.time_utils
File: src/helpershelp/api/routes/llm.py
Proposed Fix: import `helpershelp.domain.value_objects.time_utils`.
Category: Mechanical

13) Violation
From: helpershelp.api.routes.oauth_gmail
Imports: helpershelp.domain.value_objects.time_utils
File: src/helpershelp/api/routes/oauth_gmail.py
Proposed Fix: import `helpershelp.domain.value_objects.time_utils`.
Category: Mechanical

14) Violation
From: helpershelp.api.routes.oauth_gmail
Imports: helpershelp.infrastructure.security.token_manager
File: src/helpershelp/api/routes/oauth_gmail.py
Proposed Fix: use `helpershelp.infrastructure.security.token_manager` or application-level token API.
Category: Mechanical / Review

15) Violation
From: helpershelp.api.routes.oauth_gmail
Imports: helpershelp.mail.oauth_models
File: src/helpershelp/api/routes/oauth_gmail.py
Proposed Fix: canonicalize oauth model location (see item 10); prefer `helpershelp.domain.models` or `helpershelp.application.mail`.
Category: Design

16) Violation
From: helpershelp.api.routes.query
Imports: helpershelp.domain.value_objects.time_utils
File: src/helpershelp/api/routes/query.py
Proposed Fix: import `helpershelp.domain.value_objects.time_utils`.
Category: Mechanical

17) Violation
From: helpershelp.api.routes.sync
Imports: helpershelp.assistant.linking
File: src/helpershelp/api/routes/sync.py
Proposed Fix: surface linking functionality via `helpershelp.application.assistant.linking` or move linking to a domain/infrastructure module and import the appropriate facade.
Category: Design

18) Violation
From: helpershelp.api.routes.sync
Imports: helpershelp.assistant.models
File: src/helpershelp/api/routes/sync.py
Proposed Fix: import `helpershelp.domain.models`.
Category: Mechanical

19) Violation
From: helpershelp.api.routes.sync
Imports: helpershelp.assistant.sources.gcal
File: src/helpershelp/api/routes/sync.py
Proposed Fix: use an infrastructure adapter namespace, e.g. `helpershelp.infrastructure.sources.gcal` or call an application sync facade (`helpershelp.application.assistant.sync`).
Category: Design

20) Violation
From: helpershelp.api.routes.sync
Imports: helpershelp.assistant.sources.gmail
File: src/helpershelp/api/routes/sync.py
Proposed Fix: use infrastructure adapter or application facade as above.
Category: Design

21) Violation
From: helpershelp.api.routes.sync
Imports: helpershelp.domain.value_objects.time_utils
File: src/helpershelp/api/routes/sync.py
Proposed Fix: import `helpershelp.domain.value_objects.time_utils`.
Category: Mechanical

22) Violation
From: helpershelp.application.assistant.proposals
Imports: helpershelp.assistant.date_extract
File: src/helpershelp/application/assistant/proposals.py
Proposed Fix: move `date_extract` to `helpershelp.application.assistant.date_extract` (application-level helper) or a domain util if domain-specific.
Category: Design

23) Violation
From: helpershelp.application.assistant.proposals
Imports: helpershelp.assistant.language_guardrails
File: src/helpershelp/application/assistant/proposals.py
Proposed Fix: move `language_guardrails` to `helpershelp.application.assistant.language_guardrails`.
Category: Design

24) Violation
From: helpershelp.application.assistant.proposals
Imports: helpershelp.assistant.support
File: src/helpershelp/application/assistant/proposals.py
Proposed Fix: import `helpershelp.application.assistant.support` (application API) instead of assistant shim.
Category: Mechanical

25) Violation
From: helpershelp.application.assistant.sync
Imports: helpershelp.assistant.linking
File: src/helpershelp/application/assistant/sync.py
Proposed Fix: expose linking via `helpershelp.application.assistant.linking` or move linking into application layer.
Category: Design

26) Violation
From: helpershelp.application.assistant.sync
Imports: helpershelp.assistant.sources.gcal
File: src/helpershelp/application/assistant/sync.py
Proposed Fix: use infrastructure adapters under `helpershelp.infrastructure` and keep application dependent on ports/adapters.
Category: Design

27) Violation
From: helpershelp.application.assistant.sync
Imports: helpershelp.assistant.sources.gmail
File: src/helpershelp/application/assistant/sync.py
Proposed Fix: same as above — inject adapters via application configuration.
Category: Design

28) Violation
From: helpershelp.application.mail.mail_query_service
Imports: helpershelp.mail.mail_event
File: src/helpershelp/application/mail/mail_query_service.py
Proposed Fix: move `mail_event` into `helpershelp.domain.models` or expose via `helpershelp.application.mail` API.
Category: Design

29) Violation
From: helpershelp.infrastructure.security.oauth_adapter
Imports: helpershelp.mail.oauth_models
File: src/helpershelp/infrastructure/security/oauth_adapter.py
Proposed Fix: move oauth model definitions into `helpershelp.infrastructure.security` or `helpershelp.application.mail` depending on ownership; mark for design discussion.
Category: Design

30) Violation
From: helpershelp.infrastructure.security.token_manager
Imports: helpershelp.mail.oauth_models
File: src/helpershelp/infrastructure/security/token_manager.py
Proposed Fix: canonicalize OAuth models location (see items 10/29). If models are infra-specific, place them under `helpershelp.infrastructure.mail`.
Category: Design

31) Violation
From: helpershelp.retrieval.retrieval_coordinator
Imports: helpershelp.llm.embedding_service
File: src/helpershelp/retrieval/retrieval_coordinator.py
Proposed Fix: replace import with `helpershelp.infrastructure.llm.bge_m3_adapter` or depend on an LLM/embedding port (e.g. `helpershelp.ports.llm_port`) and inject concrete implementation.
Category: Mechanical / Design


---

Notes:
- After applying mechanical fixes, re-run enforcement script and tests.
- Enable CI enforcement only after violations ≤ 5.
