# Security Best Practices Review (Helper)

Scope: This report focuses on the Python/FastAPI backend in `backend/` (primary risk surface). The iOS app under `ios/` is referenced only when it directly influences backend security posture (e.g., transport/auth expectations).

## Executive summary

The backend is currently **not secure-by-default for any deployment where untrusted clients can reach it** (LAN, cloud, or even other local users). The highest-risk themes are: **missing authentication/authorization on sensitive endpoints**, **overly permissive CORS**, **unsafe token “validation” (JWT signature not verified)**, and **model-loading configuration that can execute arbitrary code (`trust_remote_code=True`)**. If the service is intended to be reachable beyond localhost, these issues are likely exploitable for data exfiltration and integrity compromise.

---

## Critical findings

### SBP-001 — No authentication/authorization on sensitive API routes (Critical)

**Impact (1 sentence):** Any network-reachable deployment would allow an attacker to ingest or retrieve sensitive mailbox/calendar-derived data, trigger sync actions, and drive expensive LLM/embedding workloads without authorization.

**Locations (examples):**
- `backend/src/helpershelp/api/app.py:68`–`74` (routers included with no global auth dependency)
- `backend/src/helpershelp/api/routes/sync.py:17`–`44` and `:47`–`79` (state-changing sync endpoints)
- `backend/src/helpershelp/api/routes/assistant.py:48`–`56` (state-changing ingest endpoint)
- `backend/src/helpershelp/api/routes/mail.py` and `backend/src/helpershelp/api/routes/query.py` (data access endpoints)

**Evidence:**
- No `Depends(...)` / `Security(...)` usage is present under `backend/src/helpershelp/api/` (router-level auth dependency is not implemented).
- Sync endpoints accept an access token and perform remote fetch + local persistence:
  - `backend/src/helpershelp/api/routes/sync.py:17`–`22` (`/sync/gmail`)
  - `backend/src/helpershelp/api/routes/sync.py:47`–`55` (`/sync/gcal`)

**Fix (secure-by-default):**
- Introduce an explicit authentication dependency (even a minimal API key for now) and attach it **router-wide** to all non-public routers.
- Default policy should be **deny**; explicitly mark only `/health` as public if needed.

**Defense-in-depth:**
- Bind the server to loopback for local-only usage.
- Add rate limiting and request body limits (see SBP-006).

---

### SBP-002 — Overly permissive CORS (`allow_origins=["*"]`, methods/headers `["*"]`) (Critical)

**Impact (1 sentence):** If the backend becomes reachable, any website can cause a victim’s browser to make cross-origin requests to this API (CORS is not auth, but permissive CORS increases exploitability and cross-site abuse).

**Location:**
- `backend/src/helpershelp/api/app.py:27`–`32`

**Evidence:**
```py
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Fix (secure-by-default):**
- Disable CORS by default.
- If a browser-based client is required, set a strict allowlist (exact origins) and restrict methods/headers to what’s needed.

---

### SBP-003 — JWT “validation” does not verify signatures (`verify_signature=False`) (Critical)

**Impact (1 sentence):** Any attacker can mint arbitrary JWTs with far-future expirations that will be treated as “valid”, enabling auth bypass anywhere this check is used (now or in future refactors).

**Location:**
- `backend/src/helpershelp/mail/oauth_service.py:57`–`61`

**Evidence:**
```py
payload = jwt.decode(
    access_token,
    options={"verify_signature": False},
    algorithms=["RS256", "HS256"]
)
```

**Fix (secure-by-default):**
- Verify JWT signatures using the provider’s JWKs and validate `iss`, `aud`, and `exp`.
- Prefer using a well-maintained Google/OAuth validation flow instead of custom offline decoding logic.

**Mitigation if immediate fix is hard:**
- Remove `/auth/validate` entirely until proper validation is implemented, or gate it behind strict auth (SBP-001) and treat the result as informational only.

---

### SBP-004 — `SentenceTransformer(... trust_remote_code=True ...)` enables arbitrary code execution (Critical)

**Impact (1 sentence):** If an attacker can influence the model files on disk (supply chain, compromised artifact, writable cache volume), `trust_remote_code=True` can execute attacker-controlled Python during model load.

**Location:**
- `backend/src/helpershelp/llm/embedding_service.py:78`–`82`

**Evidence:**
```py
self.model = SentenceTransformer(
    str(model_path),
    trust_remote_code=True,
    local_files_only=HELPERSHELP_OFFLINE
)
```

**Fix (secure-by-default):**
- Set `trust_remote_code=False` unless there is an explicit, reviewed requirement.
- Pin model artifacts to known-good hashes and store them in a read-only directory at runtime.

---

## High findings

### SBP-005 — Access tokens are accepted in request bodies for sync endpoints (High)

**Why it matters:** Passing OAuth access tokens in JSON bodies increases exposure via logging, proxies, crash reports, and accidental persistence; it also encourages treating the backend as a generic token-forwarder.

**Locations:**
- `backend/src/helpershelp/assistant/models.py:115`–`126` (request schemas include `access_token`)
- `backend/src/helpershelp/api/routes/sync.py:17`–`22` and `:47`–`55` (tokens used to call Google APIs)

**Fix:**
- Do not accept third-party access tokens directly from untrusted clients.
- Use a backend-authenticated session/user identity and retrieve tokens from a protected server-side store (encrypted at rest), or keep sync entirely on-device if this is a single-user/local tool.

---

### SBP-006 — No request size / rate limiting / workload shaping for expensive endpoints (High)

**Why it matters:** `/assistant/ingest`, `/llm/*`, `/query`, and `/sync/*` can be used for CPU/memory exhaustion and unbounded DB growth if exposed.

**Evidence anchors:**
- `backend/src/helpershelp/api/routes/assistant.py:48`–`56` (`/assistant/ingest` writes to DB)
- `backend/src/helpershelp/api/routes/llm.py:42`–`136` (multiple compute-heavy endpoints)
- `backend/src/helpershelp/api/routes/query.py:27`–`176` (retrieval + formulation pipeline)

**Fix (secure-by-default):**
- Add rate limiting (per-IP/per-user) and timeouts.
- Add Pydantic constraints (max lengths / max list sizes) for request bodies (e.g., cap `items`, `prompt`, `query`).
- Enforce payload size limits at the edge (reverse proxy) and in app for multipart if/when added.

---

### SBP-007 — `/health/details` leaks internal configuration paths (High)

**Why it matters:** Revealing filesystem paths and operational flags helps attackers tailor exploits and locate sensitive data on compromised hosts.

**Location:**
- `backend/src/helpershelp/api/routes/health.py:23`–`35`

**Evidence:**
- Returns `db_path` and `sync_loop_enabled` directly.

**Fix:**
- Keep `/health` minimal and generic for untrusted callers.
- Put details behind auth or environment gating.

---

### SBP-008 — Dependencies are unpinned (supply-chain + reproducibility risk) (High)

**Why it matters:** Unpinned dependencies make it easy to accidentally pick up vulnerable/breaking versions and complicate incident response (“what version was running?”).

**Location:**
- `backend/pyproject.toml:11`–`23` (no version pins)
- `backend/requirements.txt:1` (editable install only)

**Fix:**
- Adopt a lockfile workflow (e.g., `pip-tools`, `uv`, Poetry) with regular security updates.

---

## Medium findings

### SBP-009 — Token encryption uses a default salt fallback (Medium)

**Why it matters:** Using a fixed/default salt reduces the security margin if passphrases are weak or reused across environments.

**Location:**
- `backend/src/helpershelp/assistant/crypto.py:35`–`38`

**Evidence:**
```py
salt = ... if salt_b64 else b"helpershelp-default-salt"
```

**Fix:**
- Require an explicit random salt (and rotate it carefully) when using passphrase-derived keys, or require a full Fernet key via `HELPERSHELP_SECRET_KEY`.

---

### SBP-010 — Backend uses `load_dotenv()` (Medium)

**Why it matters:** `.env` files are convenient but frequently lead to secret sprawl and accidental exposure; they should be treated as local-dev only with strong gitignore enforcement and deployment-time secret injection.

**Location:**
- `backend/src/helpershelp/config.py:8` (calls `load_dotenv()`)
- Repo has `backend/.env` present (ignored by `.gitignore`).

**Fix:**
- Ensure `.env` is dev-only; prefer environment injection in production.
- Add a “do not run with .env in prod” guard if this will be deployed.

---

## Low findings / hygiene

### SBP-011 — iOS client hardcodes `http://localhost:8000` (Low; becomes High if used beyond local dev)

**Location:**
- `ios/Helper/Data/Services/MailManagerUpdated/HelperAPIClient.swift:14`

**Why it matters:** Plain HTTP is fine for simulator/local dev but unsafe for any networked deployment; it also makes it easy to accidentally ship insecure transport assumptions.

**Fix:**
- Use environment-based base URLs and require HTTPS for non-local builds (ATS + build configs).

---

## Secure-by-default improvement plan (suggested)

1) **Decide the intended deployment model** (strict local-only vs LAN/cloud). This affects whether the “minimum viable” control is loopback binding vs full authn/authz.
2) **Add mandatory auth** (SBP-001) and restrict CORS (SBP-002).
3) **Fix token validation** (SBP-003) or remove it until it’s correct.
4) **Remove `trust_remote_code=True`** and harden model artifact handling (SBP-004).
5) Add **rate limiting + request limits** (SBP-006).
6) Reduce information disclosure (`/health/details`) and lock dependencies (SBP-007, SBP-008).

