from __future__ import annotations

from datetime import timedelta
from typing import Iterable, cast, List

import requests
from fastapi import APIRouter, HTTPException

from helpershelp.api.deps import get_assistant_store
from helpershelp.assistant.linking import link_emails_to_events
from helpershelp.assistant.models import SyncGCalRequest, SyncGmailRequest, UnifiedItem as AssistantUnifiedItem
from helpershelp.assistant.sources.gcal import GCalAdapter
from helpershelp.assistant.sources.gmail import GmailAdapter
from helpershelp.domain.models.unified_item import UnifiedItem as DomainUnifiedItem, ItemEdge as DomainItemEdge
from helpershelp.domain.value_objects.time_utils import utcnow

router = APIRouter()


@router.post("/sync/gmail", tags=["sync"])
def sync_gmail(request: SyncGmailRequest):
    store = get_assistant_store()
    adapter = GmailAdapter(access_token=request.access_token)
    try:
        items = adapter.fetch_items(days=request.days, max_results=request.max_results)
    except requests.HTTPError as exc:
        code = exc.response.status_code if exc.response is not None else 502
        detail = "gmail_sync_failed"
        if exc.response is not None:
            try:
                payload = exc.response.json()
                detail = payload.get("error", detail)
            except Exception:
                detail = exc.response.text or detail
        store.audit("sync_gmail_fail", {"status": code, "detail": detail})
        raise HTTPException(status_code=code, detail=detail) from exc
    except requests.RequestException as exc:
        store.audit("sync_gmail_fail", {"status": 502, "detail": "network_error"})
        raise HTTPException(status_code=502, detail="gmail_sync_network_error") from exc
    domain_items = cast(Iterable[DomainUnifiedItem], items)
    inserted, updated = store.upsert_items(domain_items)
    store.audit(
        "sync_gmail",
        {
            "days": request.days,
            "max_results": request.max_results,
            "fetched": len(items),
            "inserted": inserted,
            "updated": updated,
        },
    )

    all_recent = store.list_items(since=utcnow() - timedelta(days=30), limit=5000)
    edges = link_emails_to_events(cast(List[AssistantUnifiedItem], all_recent))
    e_ins, e_upd = store.upsert_edges(cast(Iterable[DomainItemEdge], edges))
    return {
        "status": "ok",
        "fetched": len(items),
        "inserted": inserted,
        "updated": updated,
        "edges_inserted": e_ins,
        "edges_updated": e_upd,
    }


@router.post("/sync/gcal", tags=["sync"])
def sync_gcal(request: SyncGCalRequest):
    store = get_assistant_store()
    adapter = GCalAdapter(access_token=request.access_token)
    items = adapter.fetch_items(
        days_forward=request.days_forward,
        days_back=request.days_back,
        max_results=request.max_results,
    )
    domain_items = cast(Iterable[DomainUnifiedItem], items)
    inserted, updated = store.upsert_items(domain_items)
    store.audit(
        "sync_gcal",
        {
            "days_forward": request.days_forward,
            "days_back": request.days_back,
            "max_results": request.max_results,
            "fetched": len(items),
            "inserted": inserted,
            "updated": updated,
        },
    )

    all_recent = store.list_items(since=utcnow() - timedelta(days=30), limit=5000)
    edges = link_emails_to_events(cast(List[AssistantUnifiedItem], all_recent))
    e_ins, e_upd = store.upsert_edges(cast(Iterable[DomainItemEdge], edges))
    return {
        "status": "ok",
        "fetched": len(items),
        "inserted": inserted,
        "updated": updated,
        "edges_inserted": e_ins,
        "edges_updated": e_upd,
    }
