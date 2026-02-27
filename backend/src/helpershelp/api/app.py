from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from helpershelp.api.routes.health import router as health_router
from helpershelp.api.routes.process_memory import router as process_memory_router
from helpershelp.api.routes.query import router as query_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(
    title="HelperAPI - Mail Backend",
    description="Privacy-focused assistant backend",
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
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.error(
        "Unhandled error route=%s exc_type=%s",
        request.url.path,
        exc.__class__.__name__,
    )
    return _error_response(
        status.HTTP_500_INTERNAL_SERVER_ERROR,
        "Internal server error",
    )


app.include_router(query_router)
app.include_router(process_memory_router)
app.include_router(health_router)
