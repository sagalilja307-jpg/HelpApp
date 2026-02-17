# Backend Structure

## Overview

Current backend package root:

```text
backend/
├── api.py
├── pyproject.toml
├── README.md
├── docs/
├── tests/
├── tools/
└── src/helpershelp/
```

## Package layout (`src/helpershelp/`)

```text
helpershelp/
├── api/
│   ├── app.py
│   ├── deps.py
│   ├── models.py
│   └── routes/
├── application/
│   ├── assistant/
│   │   ├── proposals.py
│   │   ├── support.py
│   │   └── sync.py
│   ├── llm/
│   │   ├── llm_service.py
│   │   └── text_generation_service.py
│   └── mail/
│       └── mail_query_service.py
├── assistant/
│   ├── models.py
│   ├── linking.py
│   ├── language_guardrails.py
│   ├── date_extract.py
│   └── sources/
├── domain/
│   ├── models/
│   ├── rules/
│   ├── value_objects/
│   └── exceptions.py
├── infrastructure/
│   ├── llm/
│   │   ├── bge_m3_adapter.py
│   │   └── ollama_adapter.py
│   ├── persistence/
│   │   └── sqlite_storage.py
│   └── security/
│       ├── oauth_adapter.py
│       ├── token_manager.py
│       └── crypto_utils.py
├── mail/
│   ├── oauth_models.py
│   ├── mail_event.py
│   └── provider.py
├── ports/
└── retrieval/
    ├── content_object.py
    └── retrieval_coordinator.py
```

## Removed shim modules

The following modules were intentionally removed (2026-02-17):

- `helpershelp.assistant.sync`
- `helpershelp.llm.embedding_service`
- `helpershelp.llm.llm_service`
- `helpershelp.llm.ollama_service`
- `helpershelp.llm.text_generation_service`
- `helpershelp.mail.oauth_service`
- `helpershelp.mail.mail_query_service`

## Tooling

- `tools/shim_policy.py`: canonical removed shim list
- `tools/check_shim_imports.py`: AST scan for forbidden shim imports
- `tools/enforce_architecture.py`: architecture enforcement for removed shims
- `tools/test_bge_m3.py`: local BGE-M3 verification

## Test layout

- `tests/test_api_*`: API endpoint behavior
- `tests/test_query_*`: retrieval/query behavior
- `tests/test_shim_deprecation.py`: removed-shim regression checks + canonical imports
