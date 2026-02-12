from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter

from helpershelp.api.deps import get_assistant_store
from helpershelp.assistant.linking import link_emails_to_events
from helpershelp.assistant.models import SyncGCalRequest, SyncGmailRequest
from helpershelp.assistant.sources.gcal import GCalAdapter
from helpershelp.assistant.sources.gmail import GmailAdapter
from helpershelp.assistant.time_utils import utcnow

router = APIRouter()


@router.post("/sync/gmail", tags=["sync"])
def sync_gmail(request: SyncGmailRequest):
    store = get_assistant_store()
    adapter = GmailAdapter(access_token=request.access_token)
    items = adapter.fetch_items(days=request.days, max_results=request.max_results)
    inserted, updated = store.upsert_items(items)
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
    edges = link_emails_to_events(all_recent)
    e_ins, e_upd = store.upsert_edges(edges)
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
    inserted, updated = store.upsert_items(items)
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
    edges = link_emails_to_events(all_recent)
    e_ins, e_upd = store.upsert_edges(edges)
    return {
        "status": "ok",
        "fetched": len(items),
        "inserted": inserted,
        "updated": updated,
        "edges_inserted": e_ins,
        "edges_updated": e_upd,
    }
