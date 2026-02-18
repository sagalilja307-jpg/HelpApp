# Backend Structure Documentation

## Overview

The HelpersHelp backend is organized using a clean, modular architecture with clear separation of concerns.

```
backend/
├── api.py                    # Entry point (uvicorn shim)
├── pyproject.toml           # Dependencies and package config
├── .env.example             # Environment configuration template
├── README.md                # Quick start guide
│
├── docs/                    # Documentation
│   ├── STRUCTURE.md         # This file (architecture overview)
│   ├── MODEL_VERIFICATION.md # Model testing guide
│   ├── INSIGHT_QUERY_ARCHITECTURE.md # Snapshot DataIntent v1 model
│   ├── SOURCE_GATING_CONTRACT.md # Deprecated (no longer used)
│   └── ADDING_NEW_SOURCE.md # Playbook for new snapshot sources
│
├── src/helpershelp/         # Main application package
│   ├── config.py            # Global configuration
│   │
│   ├── api/                 # FastAPI application layer
│   │   ├── app.py          # FastAPI app setup
│   │   ├── deps.py         # Dependency injection
│   │   ├── models.py       # Pydantic request/response models
│   │   └── routes/         # API endpoints
│   │       ├── assistant.py    # Assistant settings
│   │       ├── auth.py         # Authentication
│   │       ├── health.py       # Health checks
│   │       ├── llm.py          # LLM operations
│   │       ├── mail.py         # Email operations
│   │       ├── oauth_gmail.py  # Gmail OAuth
│   │       ├── query.py        # DataIntent query endpoint
│   │       └── sync.py         # Background sync
│   │
│   ├── application/          # Use case orchestration
│   │   ├── query/            # DataIntent router
│   │
│   ├── domain/               # Domain model (entities/value objects)
│   ├── ports/                # Interface definitions (ports)
│   ├── infrastructure/       # Adapters (SQLite, Ollama, etc.)
│   │
│   ├── llm/                 # AI/ML models layer
│   │   ├── embedding_service.py      # BGE-M3 embeddings (shim)
│   │   ├── ollama_service.py         # Ollama text generation
│   │   ├── text_generation_service.py # Service facade
│   │   └── llm_service.py            # Query interpretation (LLM endpoints only)
│   │
│   ├── assistant/           # Core assistant logic
│   │   ├── models.py       # Data models
│   │   ├── storage.py      # Database layer
│   │   ├── proposals.py    # Suggestion generation
│   │   ├── scoring.py      # Priority scoring
│   │   ├── support.py      # Support level logic
│   │   ├── sync.py         # Background sync
│   │   ├── scheduling.py   # Time-based logic
│   │   ├── language_guardrails.py # Content filtering
│   │   ├── crypto.py       # Encryption utils
│   │   ├── tokens.py       # JWT tokens
│   │   ├── time_utils.py   # Date/time helpers
│   │   └── sources/        # External data sources
│   │       ├── gmail.py
│   │       └── gcal.py
│   │
│   ├── mail/                # Email integration
│   │   ├── provider.py     # Provider abstraction
│   │   ├── oauth_service.py # OAuth flows
│   │   ├── oauth_models.py  # OAuth data models
│   │   ├── mail_query_service.py # Email search
│   │   └── mail_event.py    # Email events
│   │
│   └── retrieval/           # Content retrieval
│       ├── retrieval_coordinator.py # Multi-source coordination
│       └── content_object.py        # Unified content model
│
├── tests/                   # Unit and integration tests
│   ├── test_assistant_core.py
│   ├── test_api_*.py
│   └── test_*.py
│
└── tools/                   # Development and testing tools
    ├── test_bge_m3.py      # Ollama bge-m3 verification
    └── ngrok/              # Local tunneling examples
```

## Layer Architecture

### 1. API Layer (`src/helpershelp/api/`)

**Responsibility:** HTTP interface and request handling

- **app.py**: FastAPI application setup, middleware, error handlers
- **deps.py**: Dependency injection for services (singleton pattern)
- **models.py**: Pydantic schemas for request/response validation
- **routes/**: Endpoint handlers organized by feature

**Key Principles:**
- Thin controllers (business logic in service layers)
- Consistent error responses
- Pydantic validation for all inputs
- Dependency injection for testability

### 2. LLM Layer (`src/helpershelp/llm/`)

**Responsibility:** AI model interactions

**Services:**
- `EmbeddingService`: BGE-M3 via Ollama embeddings
- `OllamaTextGenerationService`: Qwen2.5 via Ollama generation
- `QueryInterpretationService`: Query classification for LLM endpoints

**Key Principles:**
- Models never make decisions (return scores/data only)
- Single inference boundary (all model calls via Ollama)
- Explicit availability signalling (`503` for embedding-dependent endpoints)
- Clear contracts (documented input/output)

### 3. DataIntent Query Layer (`src/helpershelp/application/query/`)

**Responsibility:** Deterministic intent routing for `/query`

**Components:**
- `data_intent_router.py`: Domain/operation/timeframe/filter resolution

**Constraints:**
- Must not depend on embeddings
- Must not trigger retrieval or analytics

### 4. Assistant Layer (`src/helpershelp/assistant/`)

**Responsibility:** Core assistant intelligence

**Components:**
- **storage.py**: SQLite persistence (UnifiedItem model)
- **proposals.py**: Generate suggestions based on stored items
- **scoring.py**: Calculate priority scores
- **support.py**: Adaptive support level logic
- **sync.py**: Background email synchronization
- **scheduling.py**: Time-based operations

**Key Principles:**
- Privacy-first (all data local)
- Configurable support levels (0-3)
- Learning weights (user feedback)
- Time-critical detection

### 5. Mail Layer (`src/helpershelp/mail/`)

**Responsibility:** Email provider integration

**Components:**
- **provider.py**: Abstract provider interface
- **oauth_service.py**: Gmail OAuth 2.0 flow
- **mail_query_service.py**: Search and fetch emails
- **mail_event.py**: Email event handling

### 6. Retrieval Layer (`src/helpershelp/retrieval/`)

**Responsibility:** Multi-source content retrieval

**Components:**
- **retrieval_coordinator.py**: Coordinate multiple sources
- **content_object.py**: Unified content representation

## Data Flow

### Query Processing Pipeline (Snapshot v1)

```
1. HTTP Request
   ↓
2. DataIntentRouter (application/query/data_intent_router.py)
   ↓
3. HTTP Response with { "data_intent": { ... } }
```

### Background Sync Flow

```
1. Sync Loop (assistant/sync.py)
   ↓
2. Fetch New Emails (mail layer)
   ↓
3. Store Items (assistant/storage.py)
   ↓
4. Generate Proposals (assistant/proposals.py)
   ↓
5. Calculate Scores (assistant/scoring.py)
```

## Configuration

### Environment Variables

See `.env.example` for full list. Key variables:
