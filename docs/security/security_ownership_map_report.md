# Security Ownership Map + Bus-Factor Risks (Helper)

This report is derived from **git history** for the repo at `.` using the `security-ownership-map` tooling (people↔files graph + co-change clustering). It focuses on **sensitive code ownership** and **bus-factor risks**.

## How this was generated

Command (run from repo root):

```bash
python3 /Users/sagalilja/.codex/skills/security-ownership-map/scripts/run_ownership_map.py \
  --repo . \
  --out ownership-map-out \
  --sensitive-config sensitive-paths.csv \
  --emit-commits \
  --cochange-max-files 40
```

Outputs are in `ownership-map-out/`:
- `people.csv`, `files.csv`, `edges.csv` (ownership graph)
- `cochange_edges.csv`, `cochange.graph.json`, `communities.json` (co-change graph + communities)
- `summary.json` (bus-factor hotspots / hidden owners / orphaned sensitive code)

## Repo stats (from `ownership-map-out/summary.json`)

- Commits analyzed: 4
- People: 1
- Files: 178
- Ownership edges (touches): 195

## Key findings (high confidence)

### 1) Bus factor for sensitive code is effectively **1**

All sensitive hotspots flagged by the sensitivity config have `bus_factor: 1` and a single top owner: `sagalilja307@gmail.com` (as of latest analyzed commit time).

Sensitive areas affected (examples; see `summary.json -> bus_factor_hotspots` for the full list):
- API boundary and routing: `backend/src/helpershelp/api/**`
- Auth/token handling: `backend/src/helpershelp/mail/oauth_service.py`, `backend/src/helpershelp/api/routes/auth.py`, `backend/src/helpershelp/assistant/tokens.py`
- Crypto at rest (token encryption): `backend/src/helpershelp/assistant/crypto.py`
- Data store: `backend/src/helpershelp/assistant/storage.py`
- External API adapters: `backend/src/helpershelp/assistant/sources/gmail.py`, `.../gcal.py`
- ML runtime glue: `backend/src/helpershelp/llm/**`
- iOS client security-adjacent glue: `ios/Helper/Data/Services/MailManagerUpdated/**`

**Risk:** if the primary author is unavailable, security fixes, incident response, and safe refactors in these areas are blocked or substantially slowed.

### 2) Sensitive ownership concentration (“hidden owner” signal)

`summary.json -> hidden_owners` indicates a single person controls **100%** of every sensitive category tag in `sensitive-paths.csv` (api/auth/crypto/secrets/data_store/etc).

**Risk:** even if additional engineers contribute later, without explicit ownership assignments you can end up with “implicit single owner” patterns persisting in high-risk modules.

### 3) No “orphaned sensitive code” yet (but mostly because the repo is young)

`summary.json -> orphaned_sensitive_code` is empty, and last-touch timestamps are recent across sensitive files. That’s good, but this is primarily explained by the low commit count and recency.

## Co-change/cluster notes

With only a handful of commits, co-change clustering is not very informative yet (only 2 small communities were identified in `communities.json`). Re-run this after more development history accumulates to get meaningful clusters for “ownership drift” and team boundaries.

## Prioritized mitigations (reduce bus-factor risk)

1) **Add explicit CODEOWNERS for sensitive paths**
   - Assign at least 2 owners for:
     - `backend/src/helpershelp/api/**`
     - `backend/src/helpershelp/mail/oauth_*.py`
     - `backend/src/helpershelp/assistant/{tokens.py,crypto.py,storage.py,sync.py}`
     - `backend/src/helpershelp/llm/**`

2) **Establish a “two-person rule” for sensitive changes**
   - Require reviews from at least 1 additional maintainer for auth/crypto/storage and any changes that affect trust boundaries.

3) **Onboard a secondary maintainer via planned changes**
   - Do 2–3 small, well-scoped PRs in each sensitive area (auth, crypto, storage) led by the backup maintainer to build real operational familiarity.

4) **Document “security invariants” next to sensitive modules**
   - Short docs reduce the effective bus factor by making future ownership transfer faster.

## How to reproduce / query specific slices

Examples (bounded JSON):

```bash
python3 /Users/sagalilja/.codex/skills/security-ownership-map/scripts/query_ownership.py \
  --data-dir ownership-map-out summary --section bus_factor_hotspots

python3 /Users/sagalilja/.codex/skills/security-ownership-map/scripts/query_ownership.py \
  --data-dir ownership-map-out summary --section hidden_owners

python3 /Users/sagalilja/.codex/skills/security-ownership-map/scripts/query_ownership.py \
  --data-dir ownership-map-out files --tag auth --bus-factor-max 1
```

