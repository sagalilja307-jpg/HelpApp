from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, HTTPException, Query, status

from helpershelp.api.deps import get_assistant_store
from helpershelp.assistant.models import (
    DashboardResponse,
    IngestRequest,
    ProposalDecisionRequest,
    ProposalStatus,
    SettingsResponse,
    SettingsUpdateRequest,
)
from helpershelp.assistant.proposals import (
    generate_proposals,
    maybe_adjust_followup_days_on_feedback,
)
from helpershelp.assistant.scoring import build_dashboard_lists
from helpershelp.assistant.time_utils import utcnow

router = APIRouter()


@router.get("/dashboard", response_model=DashboardResponse, tags=["assistant"])
def dashboard(days: int = Query(default=90, ge=1, le=365)):
    store = get_assistant_store()
    now = utcnow()
    since = now - timedelta(days=int(days))

    items = store.list_items(since=since, limit=5000)
    important, upcoming, _scored = build_dashboard_lists(items, now=now)

    settings = store.get_settings()
    proposals = generate_proposals(items=items, now=now, settings=settings)
    store.upsert_proposals(proposals)

    pending = store.list_proposals(limit=200)
    return DashboardResponse(
        now=now,
        important_now=important,
        upcoming=upcoming,
        proposals=pending,
    )


@router.post("/ingest", tags=["assistant"])
def ingest(request: IngestRequest):
    store = get_assistant_store()
    inserted, updated = store.upsert_items(request.items)
    store.audit(
        "ingest",
        {"inserted": inserted, "updated": updated, "count": len(request.items)},
    )
    return {"status": "ok", "inserted": inserted, "updated": updated}


@router.post("/proposals/{proposal_id}/accept", tags=["assistant"])
def accept_proposal(proposal_id: str, request: ProposalDecisionRequest):
    store = get_assistant_store()
    updated = store.update_proposal_status(
        proposal_id,
        status=ProposalStatus.accepted,
        user_edits=request.user_edits,
    )
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Proposal not found",
        )
    store.insert_feedback(proposal_id, "accept", {"user_edits": request.user_edits})

    settings = store.get_settings()
    adjust = maybe_adjust_followup_days_on_feedback(settings, "accept")
    if adjust:
        store.upsert_settings(adjust)

    return updated


@router.post("/proposals/{proposal_id}/dismiss", tags=["assistant"])
def dismiss_proposal(proposal_id: str, request: ProposalDecisionRequest):
    store = get_assistant_store()
    updated = store.update_proposal_status(
        proposal_id,
        status=ProposalStatus.dismissed,
        user_edits=request.user_edits,
    )
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Proposal not found",
        )
    store.insert_feedback(proposal_id, "dismiss", {"user_edits": request.user_edits})

    settings = store.get_settings()
    adjust = maybe_adjust_followup_days_on_feedback(settings, "dismiss")
    if adjust:
        store.upsert_settings(adjust)

    return updated


@router.get("/settings", response_model=SettingsResponse, tags=["assistant"])
def get_settings():
    store = get_assistant_store()
    return SettingsResponse(settings=store.get_settings())


@router.post("/settings", response_model=SettingsResponse, tags=["assistant"])
def update_settings(request: SettingsUpdateRequest):
    store = get_assistant_store()
    merged = store.upsert_settings(request.settings)
    return SettingsResponse(settings=merged)
