from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from helpershelp.api.deps import get_assistant_store
from helpershelp.api.routes.assistant import router as assistant_router
from helpershelp.api.routes.auth import router as auth_router
from helpershelp.api.routes.health import router as health_router
from helpershelp.api.routes.llm import router as llm_router
from helpershelp.api.routes.mail import router as mail_router
from helpershelp.api.routes.oauth_gmail import router as oauth_gmail_router
from helpershelp.api.routes.query import router as query_router
from helpershelp.api.routes.sync import router as sync_router
from helpershelp.application.assistant.sync import start_sync_loop

try:
    import requests
except ImportError:  # pragma: no cover
    requests = None

logger = logging.getLogger(__name__)


def _model_matches(requested_model: str, available_model: str) -> bool:
    if not requested_model or not available_model:
        return False
    if requested_model == available_model:
        return True
    return available_model.startswith(requested_model.split(":")[0])


def _log_ollama_startup_status() -> None:
    ollama_host = os.getenv("OLLAMA_HOST", "http://localhost:11434")
    generation_model = os.getenv("OLLAMA_MODEL", "qwen2.5:7b")
    embedding_model = os.getenv("OLLAMA_EMBED_MODEL", "bge-m3")

    if requests is None:
        logger.warning("requests library missing - cannot verify Ollama startup status")
        return

    try:
        response = requests.get(f"{ollama_host}/api/tags", timeout=5)
        if response.status_code != 200:
            logger.warning(
                "Ollama startup check failed: %s %s",
                response.status_code,
                response.text[:500],
            )
            return

        models = response.json().get("models", [])
        model_names = [m.get("name", "") for m in models]
        missing_models = []
        for model in [generation_model, embedding_model]:
            if not any(_model_matches(model, available_model) for available_model in model_names):
                missing_models.append(model)

        if missing_models:
            logger.warning(
                "Ollama reachable at %s but missing models: %s",
                ollama_host,
                ", ".join(missing_models),
            )
        else:
            logger.info(
                "Ollama startup check passed at %s (generation=%s, embedding=%s)",
                ollama_host,
                generation_model,
                embedding_model,
            )
    except Exception as exc:
        logger.warning("Could not verify Ollama startup status: %s", exc)


@asynccontextmanager
async def lifespan(app: FastAPI):
    _log_ollama_startup_status()
    store = get_assistant_store()
    start_sync_loop(store)
    yield


app = FastAPI(
    title="HelperAPI - Mail Backend",
    description="Privacy-focused mail filtering with Ollama-only inference (qwen2.5 + bge-m3)",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _error_response(code: int, message: str):
    return JSONResponse(status_code=code, content={"error": {"message": message}})


def _is_query_alias_validation_error(exc: RequestValidationError) -> bool:
    try:
        errors = exc.errors()
    except Exception:
        return False
    for error in errors:
        message = str(error.get("msg", "")).lower()
        if "either 'query' or 'question' must be provided" in message:
            return True
    return False


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException):
    if isinstance(exc.detail, str):
        message = exc.detail
    else:
        message = "Request failed"
    return _error_response(exc.status_code, message)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(_: Request, exc: RequestValidationError):
    if _is_query_alias_validation_error(exc):
        return _error_response(status.HTTP_400_BAD_REQUEST, str(exc))
    return _error_response(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc))


@app.exception_handler(Exception)
async def unhandled_exception_handler(_: Request, exc: Exception):
    logger.error("Unhandled error: %s", exc, exc_info=True)
    return _error_response(
        status.HTTP_500_INTERNAL_SERVER_ERROR,
        "Internal server error",
    )


app.include_router(llm_router)
app.include_router(query_router)
app.include_router(auth_router)
app.include_router(oauth_gmail_router)
app.include_router(mail_router)
app.include_router(health_router)
app.include_router(assistant_router)
app.include_router(sync_router)
