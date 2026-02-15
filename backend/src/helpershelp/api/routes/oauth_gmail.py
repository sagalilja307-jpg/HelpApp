from __future__ import annotations

import os
import secrets
from datetime import timedelta
from typing import Dict
from urllib.parse import urlencode

import requests
from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel

from helpershelp.api.deps import get_assistant_store
from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.assistant.tokens import store_oauth_token
from helpershelp.mail.oauth_models import OAuthToken

router = APIRouter()

_GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
_GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
_STATE_TTL = timedelta(minutes=10)
_state_cache: Dict[str, object] = {}


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

    store = get_assistant_store()
    store.audit("oauth_gmail_start", {"provider": "gmail"})

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
        store = get_assistant_store()
        store.audit("oauth_gmail_exchange_fail", {"status": status_code, "detail": detail})
        raise HTTPException(status_code=status_code, detail=detail) from exc
    except requests.RequestException as exc:
        store = get_assistant_store()
        store.audit("oauth_gmail_exchange_fail", {"status": 502, "detail": "network_error"})
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

    store = get_assistant_store()
    persisted = store_oauth_token(store, provider="gmail", token=token)
    store.audit(
        "oauth_gmail_exchange_ok",
        {
            "provider": "gmail",
            "persisted": bool(persisted.get("stored", False)),
        },
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
        store = get_assistant_store()
        store.audit("oauth_gmail_refresh_fail", {"status": status_code, "detail": detail})
        raise HTTPException(status_code=status_code, detail=detail) from exc
    except requests.RequestException as exc:
        store = get_assistant_store()
        store.audit("oauth_gmail_refresh_fail", {"status": 502, "detail": "network_error"})
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

    store = get_assistant_store()
    persisted = store_oauth_token(store, provider="gmail", token=token)
    store.audit(
        "oauth_gmail_refresh_ok",
        {
            "provider": "gmail",
            "persisted": bool(persisted.get("stored", False)),
        },
    )

    return token
