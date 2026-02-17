# Backend Documentation

This directory contains comprehensive documentation for the HelpersHelp backend.

## Documents

### 📋 [STRUCTURE.md](STRUCTURE.md)
**Backend Architecture and Organization**

Complete guide to the backend structure including:
- Directory layout and module organization
- Layer architecture (API, LLM, Assistant, Mail, Retrieval)
- Data flow and processing pipelines
- Configuration management
- Testing strategy
- Best practices and coding guidelines

**Read this first** to understand how the backend is organized.

### 🔍 [MODEL_VERIFICATION.md](MODEL_VERIFICATION.md)
**AI Model Testing and Verification**

Step-by-step guides for verifying both AI models:
- **Ollama BGE-M3**: Semantic embeddings and ranking
- **Ollama Qwen2.5 7B**: Text generation and summarization

Includes:
- Installation instructions
- Quick test commands
- Manual verification examples
- Troubleshooting guides
- Performance benchmarks

**Use this** to verify your AI models are working correctly.
Ollama krävs för både generation och embeddings.

### 🧠 [INSIGHT_QUERY_ARCHITECTURE.md](INSIGHT_QUERY_ARCHITECTURE.md)
**Mental Model for Insight Queries**

Normativ beskrivning av:
- backend-driven source gating
- query lifecycle (query -> requirement -> ingest -> retry -> analysis)
- Apple-kompatibel user-driven dataatkomst
- designprinciper och arkitekturinvarianter

### 📜 [SOURCE_GATING_CONTRACT.md](SOURCE_GATING_CONTRACT.md)
**API Contract for Source Gating**

Normativt kontrakt for:
- `POST /query` signalfalt
- `GET /assistant/feature-status`
- `POST /ingest` med `features`
- reason codes, retryregler och felbeteende

### 🧩 [ADDING_NEW_SOURCE.md](ADDING_NEW_SOURCE.md)
**Playbook for New Insight Sources**

Steg-for-steg-mall for att lagga till en ny kalla utan arkitekturdrift:
- backend reason codes + feature-store
- iOS FeatureBuilder + pipeline integration
- dokumentations- och testkrav

## Quick Links

### Getting Started
1. [Backend README](../README.md) - Quick start and setup
2. [STRUCTURE.md](STRUCTURE.md) - Architecture overview
3. [MODEL_VERIFICATION.md](MODEL_VERIFICATION.md) - Verify models work
4. [INSIGHT_QUERY_ARCHITECTURE.md](INSIGHT_QUERY_ARCHITECTURE.md) - Insight lifecycle and responsibilities
5. [SOURCE_GATING_CONTRACT.md](SOURCE_GATING_CONTRACT.md) - API contract and reason codes
6. [ADDING_NEW_SOURCE.md](ADDING_NEW_SOURCE.md) - Extension playbook

### Fas 1 API additions
- `/query` har source-gating-signaler (`analysis_ready`, `requires_sources`, `requirement_reason_codes`, `required_time_window`)
- `GET /assistant/feature-status` returnerar kalender feature-status
- `POST /ingest` accepterar nu optional `features.calendar_events` (bakatkompatibelt med `items`)

### Start Backend (canonical flow)
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
uvicorn api:app --reload
```

### Run Tests
```bash
cd backend
source .venv/bin/activate
pytest
```

### Configuration
- [.env.example](../.env.example) - Environment variable template
- [pyproject.toml](../pyproject.toml) - Dependencies and package config

### API Documentation
When the backend is running, visit:
- `http://localhost:8000/docs` - Interactive Swagger UI
- `http://localhost:8000/redoc` - ReDoc documentation

## Documentation Organization

```
docs/
├── README.md                 # This file (navigation)
├── STRUCTURE.md             # Architecture and organization
├── MODEL_VERIFICATION.md    # Model testing guide
├── INSIGHT_QUERY_ARCHITECTURE.md  # Insight lifecycle and principles
├── SOURCE_GATING_CONTRACT.md      # Source gating API contract
└── ADDING_NEW_SOURCE.md           # New source playbook
```

## Contributing to Documentation

When adding new features or making significant changes:

1. **Update STRUCTURE.md** if you:
   - Add new modules or layers
   - Change data flows
   - Modify architecture patterns

2. **Update MODEL_VERIFICATION.md** if you:
   - Add new models
   - Change model configuration
   - Update model versions

3. **Update SOURCE_GATING_CONTRACT.md / INSIGHT_QUERY_ARCHITECTURE.md** if you:
   - Change query lifecycle
   - Change source-gating fields
   - Add/rename reason codes
   - Change retry or freshness behavior

4. **Update ADDING_NEW_SOURCE.md** if you:
   - Introduce a new source integration pattern
   - Change required extension checklist

5. **Update main README.md** if you:
   - Change setup steps
   - Add new dependencies
   - Modify quick start instructions

## Documentation Standards

- Use clear, concise language
- Include code examples where helpful
- Add troubleshooting sections for common issues
- Keep diagrams simple and ASCII-based for version control
- Link between related documents
- Update dates when making significant changes

## Need Help?

If the documentation doesn't answer your question:
1. Check the main [README.md](../README.md)
2. Review the code comments (especially service contracts)
3. Run the test suite to see examples
4. Check the API docs at `/docs` endpoint
