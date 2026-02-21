from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status

from helpershelp.api.deps import oauth_service
from helpershelp.mail.oauth_models import (
    OAuthToken,
    TokenRefreshRequest,
    TokenValidationRequest,
    TokenValidationResponse,
)

router = APIRouter()


@router.post("/auth/validate", response_model=TokenValidationResponse, tags=["auth"])
def validate_token(request: TokenValidationRequest):
    response = oauth_service.validate_token(
        access_token=request.access_token,
        provider=request.provider,
    )
    if not response.valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )
    return response


@router.post("/auth/refresh", response_model=OAuthToken, tags=["auth"])
def refresh_token(request: TokenRefreshRequest):
    new_token = oauth_service.refresh_token(
        refresh_token=request.refresh_token,
        provider=request.provider,
    )
    if not new_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Failed to refresh token",
        )
    oauth_service.store_token(request.provider, new_token)
    return new_token


@router.post("/auth/store", tags=["auth"])
def store_token(token: OAuthToken, provider: str = Query(default="gmail")):
    oauth_service.store_token(provider, token)
    return {"status": "stored", "provider": provider, "persisted": False}
