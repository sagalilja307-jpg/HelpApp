# Shim Deprecation Strategy

**Version:** 1.0  
**Created:** 2026-02-15  
**Target Removal:** Version 2.0.0 (6 months from now)

## Overview

This document outlines the strategy for deprecating and removing backward compatibility shims that were created during the Clean Architecture refactoring.

## Current Status

### Identified Shims (15 total)

#### Assistant Module Shims (`helpershelp.assistant.*`)
1. **`assistant/scoring.py`** → `domain.rules.scoring`
   - Used in: `api/routes/assistant.py`, `tests/test_assistant_core.py`
   - Exports: `ScoredItem`, `score_item`, `dedupe_scored_items`, `build_dashboard_lists`

2. **`assistant/support.py`** → `application.assistant.support`
   - Used in: `api/routes/assistant.py`, `application/assistant/proposals.py`
   - Exports: `SupportPolicy`, `resolve_support_policy`, `filter_proposals_by_policy`, etc.

3. **`assistant/sync.py`** → `application.assistant.sync`
   - Used in: `api/app.py`
   - Exports: `SyncConfig`, `SyncController`

4. **`assistant/crypto.py`** → `infrastructure.security.crypto_utils`
   - Used in: None found (candidate for early removal)
   - Exports: `get_fernet`, `encrypt_json`, `decrypt_json`

5. **`assistant/storage.py`** → `infrastructure.persistence.sqlite_storage`
   - Used in: `tests/test_query_with_notes_and_mail.py`, `tests/test_sync_gmail_authorized.py`
   - Exports: `SqliteStore`, `StoreConfig`

6. **`assistant/time_utils.py`** → `domain.value_objects.time_utils`
   - Used extensively in: `api/routes/*`, `tests/*`, `assistant/sources/*`
   - Exports: `utcnow`

7. **`assistant/tokens.py`** → `infrastructure.security.token_manager`
   - Used in: `api/routes/oauth_gmail.py`, `api/routes/auth.py`
   - Exports: `store_oauth_token`, `load_oauth_token`, `TOKENS_SETTINGS_KEY`

8. **`assistant/proposals.py`** → `application.assistant.proposals`
   - Used in: `api/routes/assistant.py`, `tests/test_assistant_core.py`
   - Exports: `ProposalConfig`, `get_proposal_config`, `generate_proposals`, `decide_proposal`

9. **`assistant/scheduling.py`** → `domain.rules.scheduling`
   - Used in: None found (candidate for early removal)
   - Exports: `TimeSlot`, `list_busy_intervals`, `suggest_free_slots`

#### LLM Module Shims (`helpershelp.llm.*`)
10. **`llm/llm_service.py`** → `application.llm.llm_service`
    - Used in: None found (candidate for early removal)
    - Exports: `QueryInterpretationService`

11. **`llm/embedding_service.py`** → `infrastructure.llm.bge_m3_adapter`
    - Used in: `retrieval/retrieval_coordinator.py`, `tools/test_bge_m3.py`
    - Exports: `EmbeddingService`, `get_embedding_service`

12. **`llm/ollama_service.py`** → `infrastructure.llm.ollama_adapter`
    - Used in: None found (candidate for early removal)
    - Exports: `OllamaTextGenerationService`, `get_ollama_text_generation_service`

13. **`llm/text_generation_service.py`** → `application.llm.text_generation_service`
    - Used in: None found (candidate for early removal)
    - Exports: `TextGenerationService`, `get_text_generation_service`

#### Mail Module Shims (`helpershelp.mail.*`)
14. **`mail/oauth_service.py`** → `infrastructure.security.oauth_adapter`
    - Used in: None found (candidate for early removal)
    - Exports: `OAuthService`

15. **`mail/mail_query_service.py`** → `application.mail.mail_query_service`
    - Used in: None found (candidate for early removal)
    - Exports: `MailQueryService`

## Implementation Status

### ✅ Completed
- [x] Identified all shim files and their usage
- [x] Created `_deprecation.py` utility module with runtime warnings
- [x] Added deprecation warnings to all 15 shim files
- [x] Warnings specify removal version (2.0.0) and correct import paths

### 🔄 In Progress
- [ ] Update all internal usage to new import paths
- [ ] Verify test suite passes with new imports
- [ ] Update documentation with migration guide

### 📅 Planned
- [ ] Remove shims in version 2.0.0 (August 2026)

## Migration Timeline

### Phase 1: Warning Period (February - April 2026)
**Duration:** 3 months  
**Goal:** Make developers aware of deprecations

- ✅ Runtime warnings emitted on every shim import
- ✅ Warnings displayed in logs and console
- Document migration paths in README
- Send team notification about deprecations
 - CI enforcement: tests run with DeprecationWarnings visible and shim-import scan

### Phase 2: Migration (May - July 2026)
**Duration:** 3 months  
**Goal:** Update all code to use new imports

#### Week 1-2: Quick Wins (Unused Shims)
Remove shims with no usage:
- `assistant/crypto.py`
- `assistant/scheduling.py`
- `llm/llm_service.py`
- `llm/ollama_service.py`
- `llm/text_generation_service.py`
- `mail/oauth_service.py`
- `mail/mail_query_service.py`

#### Week 3-6: API Layer
Update `api/routes/*`:
- Replace `assistant.time_utils` → `domain.value_objects.time_utils`
- Replace `assistant.tokens` → `infrastructure.security.token_manager`
- Replace `assistant.scoring` → `domain.rules.scoring`
- Replace `assistant.support` → `application.assistant.support`
- Replace `assistant.proposals` → `application.assistant.proposals`
- Replace `assistant.sync` → `application.assistant.sync`

#### Week 7-9: Application Layer
Update `application/*`:
- Replace legacy imports with correct architecture paths
- Ensure no application layer imports infrastructure directly

#### Week 10-12: Tests
Update all test files:
- `tests/test_assistant_core.py`
- `tests/test_query_with_notes_and_mail.py`
- `tests/test_sync_gmail_authorized.py`
- `tests/test_retrieval_source_caps_stage2.py`
- Other test files using deprecated imports

### Phase 3: Removal (August 2026)
**Duration:** Release 2.0.0  
**Goal:** Clean codebase

- Delete all shim files
- Remove `assistant/`, `llm/`, `mail/` directories (keep only new structure)
- Update pyproject.toml version to 2.0.0
- Document breaking changes in CHANGELOG

## Test Strategy

### Pre-Migration Testing
```bash
# Run full test suite with deprecation warnings visible
pytest -W default::DeprecationWarning

# Verify all tests pass
pytest --tb=short

# Check for deprecation warnings in logs
grep -r "DEPRECATION WARNING" test_output.log
```

### During Migration Testing
For each shim being removed:

1. **Find all usages:**
   ```bash
   grep -r "from helpershelp.assistant.scoring import" backend/
   ```

2. **Update imports:**
   - Change to new architecture path
   - Verify IDE doesn't show import errors

3. **Run affected tests:**
   ```bash
   pytest tests/test_assistant_core.py -v
   ```

4. **Verify no deprecation warning for that module:**
   ```bash
   pytest -W error::DeprecationWarning tests/test_assistant_core.py
   ```

5. **Run full suite:**
   ```bash
   pytest
   ```

### Post-Migration Testing
```bash
# Ensure no deprecation warnings remain
pytest -W error::DeprecationWarning

# Run integration tests
pytest tests/ -m integration

# Verify API still works
python -m pytest tests/test_api_*.py

# Check startup without warnings
python -c "from helpershelp.api.app import app; print('OK')"
```

### Continuous Monitoring
Add to CI/CD pipeline:
```yaml
# .github/workflows/test.yml
- name: Check for deprecation warnings
  run: |
    pytest -W error::DeprecationWarning 2>&1 | tee warnings.log
    if grep -q "DeprecationWarning" warnings.log; then
      echo "::warning::Deprecation warnings detected"
    fi
```

## Migration Guide for Developers

### Quick Reference

| Old Import | New Import |
|------------|------------|
| `from helpershelp.assistant.scoring import ...` | `from helpershelp.domain.rules.scoring import ...` |
| `from helpershelp.assistant.support import ...` | `from helpershelp.application.assistant.support import ...` |
| `from helpershelp.assistant.sync import ...` | `from helpershelp.application.assistant.sync import ...` |
| `from helpershelp.assistant.crypto import ...` | `from helpershelp.infrastructure.security.crypto_utils import ...` |
| `from helpershelp.assistant.storage import ...` | `from helpershelp.infrastructure.persistence.sqlite_storage import ...` |
| `from helpershelp.assistant.time_utils import ...` | `from helpershelp.domain.value_objects.time_utils import ...` |
| `from helpershelp.assistant.tokens import ...` | `from helpershelp.infrastructure.security.token_manager import ...` |
| `from helpershelp.assistant.proposals import ...` | `from helpershelp.application.assistant.proposals import ...` |
| `from helpershelp.assistant.scheduling import ...` | `from helpershelp.domain.rules.scheduling import ...` |
| `from helpershelp.llm.llm_service import ...` | `from helpershelp.application.llm.llm_service import ...` |
| `from helpershelp.llm.embedding_service import ...` | `from helpershelp.infrastructure.llm.bge_m3_adapter import ...` |
| `from helpershelp.llm.ollama_service import ...` | `from helpershelp.infrastructure.llm.ollama_adapter import ...` |
| `from helpershelp.llm.text_generation_service import ...` | `from helpershelp.application.llm.text_generation_service import ...` |
| `from helpershelp.mail.oauth_service import ...` | `from helpershelp.infrastructure.security.oauth_adapter import ...` |
| `from helpershelp.mail.mail_query_service import ...` | `from helpershelp.application.mail.mail_query_service import ...` |

### Example Migration

**Before:**
```python
from helpershelp.assistant.scoring import score_item, build_dashboard_lists
from helpershelp.assistant.time_utils import utcnow
from helpershelp.assistant.storage import SqliteStore
```

**After:**
```python
from helpershelp.domain.rules.scoring import score_item, build_dashboard_lists
from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore
```

## Risk Mitigation

### Risks
1. **Breaking external consumers:** If any external code imports these shims
2. **Test failures:** Tests might fail during migration
3. **Runtime errors:** Missing imports could cause production issues
4. **iOS app compatibility:** iOS app might use old import paths

### Mitigations
1. **Runtime warnings:** Give 6 months notice before removal
2. **Comprehensive testing:** Test strategy ensures all paths covered
3. **Gradual rollout:** Migrate one module at a time
4. **Monitoring:** CI/CD checks for deprecation warnings
5. **iOS coordination:** Coordinate with iOS team before removal

## Success Criteria

✅ **Complete when:**
- [ ] All 15 shims have runtime deprecation warnings
- [ ] Zero usages of deprecated imports in `backend/src/`
- [ ] Zero usages of deprecated imports in `backend/tests/`
- [ ] Full test suite passes without deprecation warnings
- [ ] Documentation updated with new import paths
- [ ] iOS team notified and confirmed no dependency
- [ ] Version 2.0.0 released with shims removed

## Monitoring & Metrics

Track deprecation adoption:
```bash
# Count deprecated imports in codebase
grep -r "from helpershelp.assistant\." backend/src/ | wc -l
grep -r "from helpershelp.llm\." backend/src/ | wc -l
grep -r "from helpershelp.mail\." backend/src/ | wc -l

# Should be 0 before removal
```

## References

- [CLEAN_ARCHITECTURE.md](CLEAN_ARCHITECTURE.md) - Architecture principles
- [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md) - Original refactoring details
- [STRUCTURE.md](STRUCTURE.md) - Current project structure
- [`_deprecation.py`](../src/helpershelp/_deprecation.py) - Deprecation utility

## Contact

Questions about shim deprecation? Contact architecture team or create an issue.
