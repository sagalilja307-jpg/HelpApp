## What / Why
The backend previously carried backward-compatibility shim modules (legacy import paths) to ease migration to the Clean Architecture layout.

This change removes those shim modules and treats any new imports to the removed paths as CI failures. This keeps the codebase on canonical import paths and prevents regressions back to legacy modules.

## User Impact
- Internal breaking change for backend Python imports: code that still imports the removed shim module paths will now fail at import time.
- Canonical import paths continue to work.

## Root Cause
Shim modules remained as a convenient fallback, so new code could accidentally (re)introduce legacy imports and still appear to work locally.

## Fix
- Delete the removed shim modules under `helpershelp.assistant.*`, `helpershelp.llm.*`, and `helpershelp.mail.*`.
- Centralize the list of removed shim module paths in `backend/tools/shim_policy.py`.
- Update tooling + CI to:
  - Scan for forbidden shim imports (`tools/check_shim_imports.py`).
  - Enforce architecture by blocking imports of explicitly removed shim modules (`tools/enforce_architecture.py`).
- Update docs and a small set of imports/tests/tools to use canonical paths.

## Verification
- `python tools/check_shim_imports.py`
- `python tools/enforce_architecture.py`
- `pytest -q tests/test_shim_deprecation.py`
