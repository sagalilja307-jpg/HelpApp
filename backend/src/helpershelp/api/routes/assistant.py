from __future__ import annotations

from datetime import timedelta
from typing import Any, Dict, List

from fastapi import APIRouter, HTTPException, Query, status

from helpershelp.api.deps import get_assistant_store
from helpershelp.assistant.models import (
    DashboardResponse,
    IngestRequest,
    LearningEvent,
    LearningPauseRequest,
    LearningPattern,
    LearningResetResponse,
    LearningSettingsResponse,
    ProposalDecisionRequest,
    ProposalStatus,
    SettingsResponse,
    SettingsUpdateRequest,
    SupportSettingsResponse,
    SupportSettingsUpdateRequest,
)
from helpershelp.assistant.language_guardrails import enforce_neutral_language
from helpershelp.assistant.proposals import (
    generate_proposals,
    maybe_adjust_followup_days_on_feedback,
)
from helpershelp.assistant.scoring import build_dashboard_lists
from helpershelp.assistant.support import (
    SUPPORT_ADAPTATION_ENABLED_KEY,
    SUPPORT_DAILY_CAPS_KEY,
    SUPPORT_LEVEL_KEY,
    SUPPORT_PAUSED_KEY,
    SUPPORT_TIME_CRITICAL_HOURS_KEY,
    filter_proposals_for_policy,
    learning_setting_keys,
    normalized_support_settings,
    resolve_support_policy,
    split_dashboard_items_by_policy,
    start_of_day_utc,
)
from helpershelp.assistant.time_utils import utcnow

router = APIRouter()


def _ensure_support_defaults(store) -> Dict[str, Any]:
    settings = store.get_settings()
    normalized = normalized_support_settings(settings)
    updates: Dict[str, Any] = {}
    for key, value in normalized.items():
        if settings.get(key) != value:
            updates[key] = value
    if updates:
        settings = store.upsert_settings(updates)
    return settings


def _support_response_from_settings(settings: Dict[str, Any]) -> SupportSettingsResponse:
    normalized = normalized_support_settings(settings)
    policy = resolve_support_policy(normalized)
    return SupportSettingsResponse(
        support_level=int(normalized[SUPPORT_LEVEL_KEY]),
        paused=bool(normalized[SUPPORT_PAUSED_KEY]),
        adaptation_enabled=bool(normalized[SUPPORT_ADAPTATION_ENABLED_KEY]),
        daily_caps=dict(normalized[SUPPORT_DAILY_CAPS_KEY]),
        time_critical_window_hours=int(normalized[SUPPORT_TIME_CRITICAL_HOURS_KEY]),
        effective_policy=policy.as_dict(),
    )


def _apply_daily_nudge_budget(store, proposals, policy, now):
    if policy.nudge_limit_per_day <= 0:
        return []

    day_start = start_of_day_utc(now)
    emitted_events = store.list_audit_events(
        event_types=["nudge_emitted"],
        since=day_start,
        limit=2000,
    )
    emitted_ids = {
        str(event.get("payload", {}).get("proposal_id"))
        for event in emitted_events
        if event.get("payload", {}).get("proposal_id")
    }

    already_visible = [proposal for proposal in proposals if proposal.id in emitted_ids]
    unseen = [proposal for proposal in proposals if proposal.id not in emitted_ids]

    remaining_budget = max(0, int(policy.nudge_limit_per_day) - len(emitted_ids))
    newly_visible = unseen[:remaining_budget]
    for proposal in newly_visible:
        store.audit(
            "nudge_emitted",
            {
                "proposal_id": proposal.id,
                "support_level": policy.level,
            },
        )

    return already_visible + newly_visible


def _sanitize_proposal_copy(proposals):
    for proposal in proposals:
        proposal.summary = enforce_neutral_language(proposal.summary)
        if isinstance(proposal.details, dict):
            email_payload = proposal.details.get("email")
            if isinstance(email_payload, dict):
                snippet = email_payload.get("snippet")
                if isinstance(snippet, str):
                    email_payload["snippet"] = enforce_neutral_language(snippet)
    return proposals


@router.get("/dashboard", response_model=DashboardResponse, tags=["assistant"])
def dashboard(days: int = Query(default=90, ge=1, le=365)):
    store = get_assistant_store()
    now = utcnow()
    since = now - timedelta(days=int(days))

    items = store.list_items(since=since, limit=5000)
    _important, _upcoming, scored = build_dashboard_lists(items, now=now)

    settings = _ensure_support_defaults(store)
    policy = resolve_support_policy(settings)
    important, upcoming = split_dashboard_items_by_policy(
        scored_items=scored,
        policy=policy,
        now=now,
        important_limit=3,
        upcoming_limit=20,
    )

    generated = generate_proposals(items=items, now=now, settings=settings)
    item_by_id = {item.id: item for item in items}
    generated = filter_proposals_for_policy(
        generated,
        policy=policy,
        item_by_id=item_by_id,
        now=now,
    )
    generated = _sanitize_proposal_copy(generated)
    if generated:
        store.upsert_proposals(generated)

    pending = store.list_proposals(limit=200)
    pending = filter_proposals_for_policy(
        pending,
        policy=policy,
        item_by_id=item_by_id,
        now=now,
    )
    pending = _sanitize_proposal_copy(pending)
    pending = _apply_daily_nudge_budget(store, pending, policy, now)

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
    notes_count = sum(
        1
        for item in request.items
        if str(getattr(item, "source", "")).lower() == "notes"
    )
    store.audit(
        "ingest",
        {"inserted": inserted, "updated": updated, "count": len(request.items)},
    )
    if notes_count > 0:
        store.audit("notes_imported", {"count": notes_count})
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
        store.audit(
            "adaptive_weight_changed",
            {
                "event_type": "accept",
                "updates": adjust,
            },
        )

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
        store.audit(
            "adaptive_weight_changed",
            {
                "event_type": "dismiss",
                "updates": adjust,
            },
        )

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


@router.get("/settings/support", response_model=SupportSettingsResponse, tags=["assistant"])
def get_support_settings():
    store = get_assistant_store()
    settings = _ensure_support_defaults(store)
    return _support_response_from_settings(settings)


@router.post("/settings/support", response_model=SupportSettingsResponse, tags=["assistant"])
def update_support_settings(request: SupportSettingsUpdateRequest):
    store = get_assistant_store()
    settings = _ensure_support_defaults(store)

    updates: Dict[str, Any] = {}
    if request.support_level is not None:
        if request.support_level < 0 or request.support_level > 3:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="support_level must be between 0 and 3",
            )
        updates[SUPPORT_LEVEL_KEY] = int(request.support_level)
    if request.paused is not None:
        updates[SUPPORT_PAUSED_KEY] = bool(request.paused)
    if request.adaptation_enabled is not None:
        updates[SUPPORT_ADAPTATION_ENABLED_KEY] = bool(request.adaptation_enabled)

    if not updates:
        return _support_response_from_settings(settings)

    merged = store.upsert_settings(updates)

    if SUPPORT_LEVEL_KEY in updates:
        store.audit(
            "support_level_changed",
            {
                "from": settings.get(SUPPORT_LEVEL_KEY),
                "to": updates[SUPPORT_LEVEL_KEY],
            },
        )
    if SUPPORT_ADAPTATION_ENABLED_KEY in updates:
        store.audit(
            "adaptation_toggled",
            {
                "enabled": updates[SUPPORT_ADAPTATION_ENABLED_KEY],
                "source": "support_settings_update",
            },
        )

    return _support_response_from_settings(merged)


@router.get("/settings/learning", response_model=LearningSettingsResponse, tags=["assistant"])
def get_learning_settings():
    store = get_assistant_store()
    settings = _ensure_support_defaults(store)
    policy = resolve_support_policy(settings)

    keys = learning_setting_keys(settings)
    patterns = [
        LearningPattern(
            key=key,
            value=settings.get(key),
        )
        for key in keys
    ]
    events = [
        LearningEvent(**event)
        for event in store.list_audit_events(
            event_types=["adaptive_weight_changed", "learning_reset", "adaptation_toggled"],
            limit=200,
        )
    ]

    return LearningSettingsResponse(
        adaptation_enabled=policy.adaptation_enabled,
        patterns=patterns,
        events=events,
    )


@router.post("/settings/learning/pause", response_model=LearningSettingsResponse, tags=["assistant"])
def pause_learning(request: LearningPauseRequest):
    store = get_assistant_store()
    merged = store.upsert_settings(
        {SUPPORT_ADAPTATION_ENABLED_KEY: not request.paused}
    )
    store.audit(
        "adaptation_toggled",
        {
            "enabled": not request.paused,
            "source": "learning_pause_endpoint",
        },
    )
    _ = merged
    return get_learning_settings()


@router.post("/settings/learning/reset", response_model=LearningResetResponse, tags=["assistant"])
def reset_learning():
    store = get_assistant_store()
    settings = store.get_settings()
    keys = learning_setting_keys(settings)
    removed_count = store.delete_settings(keys)
    store.audit(
        "learning_reset",
        {
            "removed_keys": keys,
            "removed_count": removed_count,
        },
    )
    return LearningResetResponse(
        removed_keys=keys,
        removed_count=removed_count,
    )
