# Refactoring Summary

## Historical milestone

The backend was refactored toward clean architecture during February 2026:

- domain/application/infrastructure/ports layering introduced
- legacy compatibility shims were temporarily added
- deprecation utilities and migration checks were introduced

## Current status update (2026-02-17)

Shim migration is complete and shim modules are removed.

Completed in this update:

1. Internal imports migrated to canonical modules.
2. Removed 7 historical shim modules.
3. Replaced broad namespace shim detection with explicit policy.
4. Updated CI checks to run script-based enforcement.
5. Rewrote backend docs to match current code reality.

## Removed shim paths

- `helpershelp.assistant.sync`
- `helpershelp.llm.embedding_service`
- `helpershelp.llm.llm_service`
- `helpershelp.llm.ollama_service`
- `helpershelp.llm.text_generation_service`
- `helpershelp.mail.oauth_service`
- `helpershelp.mail.mail_query_service`

## Internal compatibility decision

This was accepted as an internal breaking change.
No public package publishing or external consumer contract was active at removal time.

## Remaining follow-up work (out of scope for this change)

Potential future modularization candidates:

- move `assistant.language_guardrails` closer to application/domain policy modules
- move `assistant.date_extract` to a clearer rule/value-object location
- move `assistant.sources.*` into explicit infrastructure adapter namespace

These are architecture cleanups, not shim blockers.
