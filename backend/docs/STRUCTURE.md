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
│   └── MODEL_VERIFICATION.md # Model testing guide
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
│   │       ├── query.py        # Unified query endpoint
│   │       └── sync.py         # Background sync
│   │
│   ├── llm/                 # AI/ML models layer
│   │   ├── embedding_service.py      # BGE-M3 embeddings (Ollama-backed shim)
│   │   ├── ollama_service.py         # Ollama text generation
│   │   ├── text_generation_service.py # Service facade
│   │   └── llm_service.py            # Query interpretation
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
- `QueryInterpretationService`: Query classification (uses embeddings)

**Key Principles:**
- Models never make decisions (return scores/data only)
- Single inference boundary (all model calls via Ollama)
- Explicit availability signalling (`503` for embedding-dependent endpoints)
- Clear contracts (documented input/output)

### 3. Assistant Layer (`src/helpershelp/assistant/`)

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

### 4. Mail Layer (`src/helpershelp/mail/`)

**Responsibility:** Email provider integration

**Components:**
- **provider.py**: Abstract provider interface
- **oauth_service.py**: Gmail OAuth 2.0 flow
- **mail_query_service.py**: Search and fetch emails
- **mail_event.py**: Email event handling

**Key Principles:**
- Provider abstraction (easy to add new providers)
- Secure OAuth flow
- Rate limiting awareness
- Minimal data retention

### 5. Retrieval Layer (`src/helpershelp/retrieval/`)

**Responsibility:** Multi-source content retrieval

**Components:**
- **retrieval_coordinator.py**: Coordinate multiple sources
- **content_object.py**: Unified content representation

**Key Principles:**
- Source abstraction
- Semantic ranking (via LLM layer)
- Per-source limits
- Balanced results

## Data Flow

### Query Processing Pipeline

```
1. HTTP Request
   ↓
2. API Layer (routes/query.py)
   ↓
3. Query Interpretation (LLM layer)
   - Intent classification
   - Topic extraction
   ↓
4. Content Retrieval (Retrieval layer)
   - Fetch from sources (mail, assistant_store)
   - Semantic ranking (Ollama bge-m3 embeddings)
   - Apply filters and limits
   ↓
5. Text Generation (LLM layer)
   - Formulate response (Ollama qwen2.5:7b)
   ↓
6. HTTP Response
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

**Models:**
- `OLLAMA_HOST`: Ollama server URL
- `OLLAMA_MODEL`: Generation model (default: qwen2.5:7b)
- `OLLAMA_EMBED_MODEL`: Embedding model (default: bge-m3)

**Storage:**
- `HELPERSHELP_DB_PATH`: SQLite database path

**Features:**
- `HELPERSHELP_ENABLE_SYNC_LOOP`: Background sync enabled

### Configuration Loading

Configuration is loaded in `config.py`:
1. Load `.env` file (if exists)
2. Read environment variables
3. Set defaults

## Testing Strategy

### Test Organization

```
tests/
├── test_assistant_core.py        # Core logic tests
├── test_api_*.py                 # API endpoint tests
├── test_query_*.py               # Query pipeline tests
└── test_retrieval_*.py           # Retrieval tests
```

### Running Tests

```bash
# All tests
pytest

# Specific test file
pytest tests/test_api_query_assistant_store.py

# Specific test case
pytest tests/test_query_stage2_sources.py -k contacts -q
```

### Test Fixtures

- Tests use `tempfile.TemporaryDirectory()` for databases
- FastAPI `TestClient` for API tests
- Mock services for external dependencies

## Development Tools

### Model Verification

```bash
# Test Ollama embeddings (bge-m3)
python tools/test_bge_m3.py

# Test Ollama
curl http://localhost:11434/api/tags
```

### Local Development

```bash
# Create + activate venv (first time)
python3 -m venv .venv
source .venv/bin/activate

# Install in development mode
python -m pip install --upgrade pip
pip install -e .

# Run with auto-reload
uvicorn api:app --reload

# Run with debug logging
LOG_LEVEL=DEBUG uvicorn api:app
```

## Best Practices

### Code Organization

1. **Separation of Concerns**: Each layer has clear responsibilities
2. **Dependency Direction**: Flow from API → Services → Data
3. **No Circular Dependencies**: Use dependency injection
4. **Clear Interfaces**: Document service contracts

### Error Handling

1. **Strict Availability for Embeddings**: Return `503` when embedding backend is unavailable
2. **Informative Errors**: Clear error messages for API users
3. **Logging**: Log errors with context, not secrets
4. **HTTP Status Codes**: Use appropriate codes (400, 404, 500, 503)

### Performance

1. **Singleton Services**: Avoid reloading models
2. **Connection Pooling**: Reuse HTTP clients
3. **Lazy Loading**: Load models only when needed
4. **Batch Operations**: Use batch APIs when possible

### Security

1. **No Secrets in Code**: Use environment variables
2. **Input Validation**: Pydantic schemas for all inputs
3. **SQL Injection Prevention**: Use parameterized queries
4. **Local-First**: No external API calls (privacy)

## Adding New Features

### Adding a New API Endpoint

1. Define Pydantic models in `api/models.py`
2. Create route handler in `api/routes/`
3. Register router in `api/app.py`
4. Add tests in `tests/`

### Adding a New Data Source

1. Create fetcher function in appropriate module
2. Register with `RetrievalCoordinator`
3. Map to `ContentObject` format
4. Add tests

### Adding a New Model

1. Create service class in `llm/`
2. Implement clear contract (input/output)
3. Add singleton accessor
4. Update health check
5. Document in MODEL_VERIFICATION.md

## Troubleshooting

### Common Issues

**Import Errors:**
- Ensure `pip install -e .` was run
- Check Python path includes `src/`

**Model Not Loading:**
- Check internet connection (first download)
- Verify model cache directory exists
- See MODEL_VERIFICATION.md

**Database Errors:**
- Check `HELPERSHELP_DB_PATH` is writable
- Delete and recreate if corrupted

**API Errors:**
- Check logs: `uvicorn api:app --log-level debug`
- Verify all services are initialized
- Check health endpoint: `/health/details`

## Future Improvements

### Planned Enhancements

1. **Model Abstraction Layer**: Support multiple LLM backends
2. **Streaming Responses**: Support SSE for real-time output
3. **Rate Limiting**: Protect against abuse
4. **Caching Layer**: Redis for frequent queries
5. **Metrics**: Prometheus metrics endpoint
6. **Docker**: Containerized deployment

### Architecture Evolution

- Consider microservices if scaling needed
- Add message queue for async operations
- Separate read/write databases for scaling
- Add API versioning for breaking changes

## References

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Pydantic Documentation](https://docs.pydantic.dev/)
- [Ollama Documentation](https://ollama.com/docs)
- [Sentence Transformers](https://www.sbert.net/)
