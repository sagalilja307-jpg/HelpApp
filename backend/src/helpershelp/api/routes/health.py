from __future__ import annotations

import os
from typing import Dict, List

from fastapi import APIRouter

from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.config import DEFAULT_DB_PATH, OLLAMA_EMBED_MODEL, OLLAMA_HOST, OLLAMA_MODEL

try:
    import requests
except ImportError:  # pragma: no cover
    requests = None

router = APIRouter()


def _model_matches(requested_model: str, available_model: str) -> bool:
    if not requested_model or not available_model:
        return False
    if requested_model == available_model:
        return True
    return available_model.startswith(requested_model.split(":")[0])


def _probe_ollama() -> Dict:
    ollama_host = os.getenv("OLLAMA_HOST", OLLAMA_HOST)
    generation_model = os.getenv("OLLAMA_MODEL", OLLAMA_MODEL)
    embedding_model = os.getenv("OLLAMA_EMBED_MODEL", OLLAMA_EMBED_MODEL)

    if requests is None:
        return {
            "generation_model": generation_model,
            "embedding_model": embedding_model,
            "ollama_reachable": False,
            "missing_models": [generation_model, embedding_model],
        }

    missing_models: List[str] = [generation_model, embedding_model]
    try:
        response = requests.get(f"{ollama_host}/api/tags", timeout=5)
        if response.status_code != 200:
            return {
                "generation_model": generation_model,
                "embedding_model": embedding_model,
                "ollama_reachable": False,
                "missing_models": missing_models,
            }

        model_names = [model.get("name", "") for model in response.json().get("models", [])]
        missing_models = [
            model
            for model in [generation_model, embedding_model]
            if not any(_model_matches(model, available) for available in model_names)
        ]

        return {
            "generation_model": generation_model,
            "embedding_model": embedding_model,
            "ollama_reachable": True,
            "missing_models": missing_models,
        }
    except Exception:
        return {
            "generation_model": generation_model,
            "embedding_model": embedding_model,
            "ollama_reachable": False,
            "missing_models": missing_models,
        }


@router.get("/health", tags=["system"])
def health_check():
    return {"status": "ok"}


@router.get("/healthz", tags=["system"])
def health_check_extended():
    return {"status": "ok", "timestamp": utcnow().isoformat()}


@router.get("/health/details", tags=["system"])
def health_details():
    db_path = os.getenv("HELPERSHELP_DB_PATH", str(DEFAULT_DB_PATH))
    llm_status = _probe_ollama()
    return {
        "status": "ok",
        "timestamp": utcnow().isoformat(),
        "db_path": db_path,
        "sync_loop_enabled": os.getenv("HELPERSHELP_ENABLE_SYNC_LOOP", "0") == "1",
        "llm": llm_status,
        "model": {
            "embedding": f"{llm_status['embedding_model']} (Ollama)",
            "generation": f"{llm_status['generation_model']} (Ollama)",
        },
    }
