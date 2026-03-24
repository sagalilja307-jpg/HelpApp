from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from helpershelp.core.config import get_cors_allow_origins
from helpershelp.core.logging_config import build_log_extra, configure_logging

configure_logging()

from helpershelp.api.routes.health import router as health_router
from helpershelp.api.routes.process_memory import router as process_memory_router
from helpershelp.api.routes.query import router as query_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


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


async def http_exception_handler(_: Request, exc: HTTPException):
    if isinstance(exc.detail, str):
        message = exc.detail
    else:
        message = "Request failed"
    return _error_response(exc.status_code, message)


async def validation_exception_handler(_: Request, exc: RequestValidationError):
    if _is_query_alias_validation_error(exc):
        return _error_response(status.HTTP_400_BAD_REQUEST, str(exc))
    return _error_response(status.HTTP_422_UNPROCESSABLE_CONTENT, str(exc))


async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.error(
        "Unhandled error route=%s exc_type=%s",
        request.url.path,
        exc.__class__.__name__,
        extra=build_log_extra(
            route=request.url.path,
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            exc_type=exc.__class__.__name__,
        ),
    )
    return _error_response(
        status.HTTP_500_INTERNAL_SERVER_ERROR,
        "Internal server error",
    )


def create_app() -> FastAPI:
    application = FastAPI(
        title="HelperAPI - Mail Backend",
        description="Privacy-focused assistant backend",
        lifespan=lifespan,
    )

    application.add_middleware(
        CORSMiddleware,
        allow_origins=get_cors_allow_origins(),
        allow_methods=["*"],
        allow_headers=["*"],
    )
    application.add_exception_handler(HTTPException, http_exception_handler)
    application.add_exception_handler(RequestValidationError, validation_exception_handler)
    application.add_exception_handler(Exception, unhandled_exception_handler)
    application.include_router(query_router)
    application.include_router(process_memory_router)
    application.include_router(health_router)
    return application


app = create_app()
