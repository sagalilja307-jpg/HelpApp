from __future__ import annotations

import logging
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
from helpershelp.assistant.sync import start_sync_loop

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    store = get_assistant_store()
    start_sync_loop(store)
    yield


app = FastAPI(
    title="HelperAPI - Mail Backend",
    description="Privacy-focused mail filtering with GPT-SW3 + BGE-M3",
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


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException):
    if isinstance(exc.detail, str):
        message = exc.detail
    else:
        message = "Request failed"
    return _error_response(exc.status_code, message)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(_: Request, exc: RequestValidationError):
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
