# Clean Architecture

## Current architecture

`helpershelp` is organized into explicit layers:

- `domain/`: core models and business rules
- `application/`: use-cases and orchestration
- `ports/`: interfaces/contracts
- `infrastructure/`: adapters and concrete implementations
- `api/`: HTTP transport (FastAPI)
- `assistant/`, `mail/`: active feature modules still used by the application (not blanket shims)

## Dependency direction

Allowed direction:

- `api` -> `application` / `infrastructure` / stable contracts
- `application` -> `domain` / feature helpers / infrastructure adapters where currently required
- `infrastructure` -> `domain` / `ports`
- `domain` -> no framework dependencies

## Shim status

As of 2026-02-17, historical shim modules were removed:

- `helpershelp.assistant.sync`
- `helpershelp.llm.embedding_service`
- `helpershelp.llm.llm_service`
- `helpershelp.llm.ollama_service`
- `helpershelp.llm.text_generation_service`
- `helpershelp.mail.oauth_service`
- `helpershelp.mail.mail_query_service`

Use canonical replacements documented in `docs/SHIM_DEPRECATION_STRATEGY.md`.

## Practical rules

1. Do not import removed shim paths.
2. Do not use `helpershelp.assistant.support`; use `helpershelp.application.assistant.support`.
3. Keep domain models/rules free from FastAPI/Pydantic/Ollama/storage concerns.
4. Add architecture exceptions only through explicit review and documentation.

## Enforcement

Run:

```bash
python tools/check_shim_imports.py
python tools/enforce_architecture.py
```

Both checks are also executed in CI.
