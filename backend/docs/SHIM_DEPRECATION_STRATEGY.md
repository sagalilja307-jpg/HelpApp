# Shim Deprecation Strategy

## Status

- Created: 2026-02-15
- Completed: 2026-02-17
- Scope: internal backend only

This strategy is now completed. Historical shim modules were removed after all internal imports were migrated.

## Removed shim modules

| Removed module | Replacement module |
|---|---|
| `helpershelp.assistant.sync` | `helpershelp.application.assistant.sync` |
| `helpershelp.llm.embedding_service` | `helpershelp.infrastructure.llm.bge_m3_adapter` |
| `helpershelp.llm.llm_service` | `helpershelp.application.llm.llm_service` |
| `helpershelp.llm.ollama_service` | `helpershelp.infrastructure.llm.ollama_adapter` |
| `helpershelp.llm.text_generation_service` | `helpershelp.application.llm.text_generation_service` |
| `helpershelp.mail.oauth_service` | `helpershelp.infrastructure.security.oauth_adapter` |
| `helpershelp.mail.mail_query_service` | `helpershelp.application.mail.mail_query_service` |

## Additional path correction

The following legacy path was not a valid shim and is now fully removed from internal imports:

- `helpershelp.assistant.support` -> `helpershelp.application.assistant.support`

## Enforcement

Enforcement is now explicit and centralized via:

- `tools/shim_policy.py` (canonical list)
- `tools/check_shim_imports.py` (AST import scan in `src/`, `tests/`, `tools/`)
- `tools/enforce_architecture.py` (architecture rule against removed shims)

CI workflows use these scripts:

- `.github/workflows/pre_push_check.yml`
- `.github/workflows/test_and_shim_checks.yml`

## Verification checklist

- [x] No internal imports to removed shim paths in `src/`, `tests/`, `tools/`
- [x] No internal imports to `helpershelp.assistant.support`
- [x] Shim checker passes
- [x] Architecture checker passes
- [x] Documentation updated to current state

## Migration reference

Use this command to find forbidden imports:

```bash
rg -n "helpershelp\\.assistant\\.sync|helpershelp\\.llm\\.embedding_service|helpershelp\\.llm\\.llm_service|helpershelp\\.llm\\.ollama_service|helpershelp\\.llm\\.text_generation_service|helpershelp\\.mail\\.oauth_service|helpershelp\\.mail\\.mail_query_service|helpershelp\\.assistant\\.support" src tests tools
```

## Compatibility note

This was accepted as an internal breaking change. No external package publishing was in use for `helpershelp` at time of removal.
