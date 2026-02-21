from __future__ import annotations

import os
import secrets
from datetime import datetime, timedelta
from typing import Dict
from urllib.parse import urlencode

import requests
from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel

from helpershelp.core.time_utils import utcnow
from helpershelp.mail.oauth_models import OAuthToken

router = APIRouter()

_GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
_GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
_STATE_TTL = timedelta(minutes=10)
_state_cache: Dict[str, datetime] = {}


def _client_id() -> str:
    client_id = os.getenv("HELPERSHELP_GMAIL_CLIENT_ID")
    if not client_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Gmail OAuth client id not configured",
        )
    return client_id


def _client_secret() -> str:
    secret = os.getenv("HELPERSHELP_GMAIL_CLIENT_SECRET")
    if not secret:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Gmail OAuth client secret not configured",
        )
    return secret


def _cleanup_expired_states() -> None:
    now = utcnow()
    expired = [key for key, expires_at in _state_cache.items() if expires_at < now]
    for key in expired:
        _state_cache.pop(key, None)


def _register_state() -> str:
    _cleanup_expired_states()
    state = secrets.token_urlsafe(24)
    _state_cache[state] = utcnow() + _STATE_TTL
    return state


def _consume_state(state: str) -> None:
    _cleanup_expired_states()
    expires_at = _state_cache.pop(state, None)
    if not expires_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OAuth state",
        )


class GmailStartResponse(BaseModel):
    authorization_url: str
    state: str
    expires_in: int


class GmailExchangeRequest(BaseModel):
    code: str
    code_verifier: str
    state: str
    redirect_uri: str


class GmailRefreshRequest(BaseModel):
    refresh_token: str


@router.get("/oauth/gmail/start", response_model=GmailStartResponse, tags=["oauth"])
def gmail_start(
    code_challenge: str = Query(min_length=43, max_length=128),
    redirect_uri: str = Query(default="helper-oauth://oauth/gmail/callback"),
):
    state = _register_state()

    query = {
        "response_type": "code",
        "client_id": _client_id(),
        "redirect_uri": redirect_uri,
        "scope": "https://www.googleapis.com/auth/gmail.readonly",
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }
    auth_url = f"{_GOOGLE_AUTH_URL}?{urlencode(query)}"

    return GmailStartResponse(
        authorization_url=auth_url,
        state=state,
        expires_in=int(_STATE_TTL.total_seconds()),
    )


@router.post("/oauth/gmail/exchange", response_model=OAuthToken, tags=["oauth"])
def gmail_exchange(request: GmailExchangeRequest):
    _consume_state(request.state)

    token_payload = {
        "grant_type": "authorization_code",
        "code": request.code,
        "client_id": _client_id(),
        "client_secret": _client_secret(),
        "redirect_uri": request.redirect_uri,
        "code_verifier": request.code_verifier,
    }

    try:
        response = requests.post(_GOOGLE_TOKEN_URL, data=token_payload, timeout=20)
        response.raise_for_status()
    except requests.HTTPError as exc:
        status_code = exc.response.status_code if exc.response is not None else 502
        detail = "Gmail token exchange failed"
        if exc.response is not None:
            try:
                payload = exc.response.json()
                detail = payload.get("error", detail)
            except Exception:
                detail = exc.response.text or detail
        raise HTTPException(status_code=status_code, detail=detail) from exc
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Network error while exchanging Gmail code",
        ) from exc

    payload = response.json()
    token = OAuthToken(
        access_token=payload.get("access_token", ""),
        refresh_token=payload.get("refresh_token"),
        expires_in=int(payload.get("expires_in", 3600)),
        token_type=payload.get("token_type", "Bearer"),
    )

    return token


@router.post("/oauth/gmail/refresh", response_model=OAuthToken, tags=["oauth"])
def gmail_refresh(request: GmailRefreshRequest):
    token_payload = {
        "grant_type": "refresh_token",
        "refresh_token": request.refresh_token,
        "client_id": _client_id(),
        "client_secret": _client_secret(),
    }

    try:
        response = requests.post(_GOOGLE_TOKEN_URL, data=token_payload, timeout=20)
        response.raise_for_status()
    except requests.HTTPError as exc:
        status_code = exc.response.status_code if exc.response is not None else 502
        detail = "Gmail token refresh failed"
        if exc.response is not None:
            try:
                payload = exc.response.json()
                detail = payload.get("error", detail)
            except Exception:
                detail = exc.response.text or detail
        raise HTTPException(status_code=status_code, detail=detail) from exc
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Network error while refreshing Gmail token",
        ) from exc

    payload = response.json()
    token = OAuthToken(
        access_token=payload.get("access_token", ""),
        refresh_token=payload.get("refresh_token") or request.refresh_token,
        expires_in=int(payload.get("expires_in", 3600)),
        token_type=payload.get("token_type", "Bearer"),
    )

    return token
