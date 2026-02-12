from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from helpershelp.assistant.language_guardrails import enforce_neutral_language
from helpershelp.assistant.models import Proposal, ProposalDecisionRequest, ProposalType, UnifiedItem, UnifiedItemType
from helpershelp.assistant.support import adaptation_allowed, clamp_follow_up_days, resolve_support_policy
from helpershelp.assistant.date_extract import extract_due_at
from helpershelp.assistant.scheduling import suggest_free_slots
from helpershelp.assistant.time_utils import utcnow


def _as_utc_naive(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


@dataclass(frozen=True)
class ProposalConfig:
    follow_up_days: int = 3
    schedule_duration_minutes: int = 120


def get_proposal_config(settings: Dict[str, Any]) -> ProposalConfig:
    days = settings.get("assistant.follow_up_days", 3)
    try:
        days = int(days)
    except Exception:
        days = 3
    days = max(1, min(14, days))

    duration = settings.get("assistant.schedule_duration_minutes", 120)
    try:
        duration = int(duration)
    except Exception:
        duration = 120
    duration = max(15, min(8 * 60, duration))

    return ProposalConfig(follow_up_days=days, schedule_duration_minutes=duration)


def _email_is_followup_candidate(item: UnifiedItem, now: datetime, follow_up_days: int) -> Tuple[bool, str]:
    if item.type != UnifiedItemType.email:
        return False, "not_email"

    status = item.status or {}
    email_status = status.get("email", status)
    direction = (email_status.get("direction") or "").lower()
    is_replied = email_status.get("is_replied")

    if direction != "inbound":
        return False, "not_inbound"

    if is_replied is True:
        return False, "already_replied"

    created = _as_utc_naive(item.created_at)
    age_days = (now - created).total_seconds() / 86400.0
    if age_days < follow_up_days:
        return False, "too_recent"

    # Only create follow-ups when we are reasonably confident it's open
    if is_replied is False:
        return True, "unreplied"
    # Reply status unknown: require a question mark hint to reduce noise
    if "?" in (item.title or "") or "?" in (item.body or ""):
        return True, "question_hint"
    return False, "unknown_reply_no_hint"


def generate_follow_up_proposals(items: List[UnifiedItem], now: datetime, cfg: ProposalConfig) -> List[Proposal]:
    proposals: List[Proposal] = []
    for it in items:
        ok, reason = _email_is_followup_candidate(it, now, cfg.follow_up_days)
        if not ok:
            continue

        summary = enforce_neutral_language(f"Följ upp: {it.title or 'Obesvarat mail'}")
        why = {
            "rule": "follow_up_email",
            "reason": reason,
            "follow_up_days": cfg.follow_up_days,
            "item_id": it.id,
        }
        details = {
            "email": {
                "subject": it.title,
                "snippet": (it.body or "")[:240],
            }
        }
        actions = {
            "type": "follow_up",
            "item_id": it.id,
            "suggested": {
                "kind": "remind",
                "after_days": 1,
            },
        }
        proposals.append(
            Proposal(
                proposal_type=ProposalType.follow_up,
                summary=summary,
                details=details,
                why=why,
                actions=actions,
                related_item_ids=[it.id],
                expires_at=now + timedelta(days=14),
            )
        )
    return proposals


def generate_create_reminder_proposals(items: List[UnifiedItem], now: datetime) -> List[Proposal]:
    proposals: List[Proposal] = []
    for it in items:
        if it.type != UnifiedItemType.email:
            continue

        status = it.status or {}
        email_status = status.get("email", status)
        direction = (email_status.get("direction") or "").lower()
        if direction != "inbound":
            continue

        # Only suggest if there's a due-ish hint
        due = extract_due_at(f"{it.title}\n{it.body}", now=now)
        if not due:
            continue

        # Keep suggestions near-term to avoid spam
        if due - now > timedelta(days=14):
            continue

        summary = enforce_neutral_language(f"Skapa påminnelse: {it.title or 'Mail'}")
        why = {
            "rule": "create_reminder_from_email_date_hint",
            "due_at": due.isoformat(),
            "item_id": it.id,
        }
        details = {
            "email": {"subject": it.title, "snippet": (it.body or "")[:240]},
            "reminder": {"title": it.title or "Påminnelse", "due_at": due.isoformat()},
        }
        actions = {
            "type": "create_reminder",
            "item_id": it.id,
            "title": it.title or "Påminnelse",
            "due_at": due.isoformat(),
            "provider": "ios_push",
        }
        proposals.append(
            Proposal(
                proposal_type=ProposalType.create_reminder,
                summary=summary,
                details=details,
                why=why,
                actions=actions,
                related_item_ids=[it.id],
                expires_at=due,
            )
        )
    return proposals


def generate_schedule_timeblock_proposals(
    items: List[UnifiedItem],
    events: List[UnifiedItem],
    now: datetime,
    cfg: ProposalConfig,
) -> List[Proposal]:
    proposals: List[Proposal] = []
    for it in items:
        if it.type not in (UnifiedItemType.task, UnifiedItemType.reminder):
            continue

        status = it.status or {}
        if status.get("state") == "done" or status.get("completed") is True:
            continue

        if not it.due_at:
            continue

        due = _as_utc_naive(it.due_at)
        if due <= now:
            continue

        # Only propose for near-term work (next 7 days)
        if due - now > timedelta(days=7):
            continue

        slots = suggest_free_slots(
            events=events,
            now=now,
            latest_end=due,
            duration_minutes=cfg.schedule_duration_minutes,
            max_slots=2,
        )
        if not slots:
            continue

        summary = enforce_neutral_language(f"Föreslå tid: {it.title or 'Uppgift'}")
        why = {
            "rule": "schedule_timeblock_before_due",
            "duration_minutes": cfg.schedule_duration_minutes,
            "due_at": due.isoformat(),
            "item_id": it.id,
        }
        details = {
            "task": {"title": it.title, "due_at": due.isoformat()},
            "recommended_slots": [{"start_at": s.start_at.isoformat(), "end_at": s.end_at.isoformat()} for s in slots],
        }
        actions = {
            "type": "schedule_timeblock",
            "item_id": it.id,
            "duration_minutes": cfg.schedule_duration_minutes,
            "recommended_slots": [{"start_at": s.start_at.isoformat(), "end_at": s.end_at.isoformat()} for s in slots],
            "provider": "gcal",
        }
        proposals.append(
            Proposal(
                proposal_type=ProposalType.schedule_timeblock,
                summary=summary,
                details=details,
                why=why,
                actions=actions,
                related_item_ids=[it.id],
                expires_at=due,
            )
        )
    return proposals


def generate_proposals(
    items: List[UnifiedItem],
    now: Optional[datetime],
    settings: Dict[str, Any],
) -> List[Proposal]:
    now = _as_utc_naive(now or utcnow())
    cfg = get_proposal_config(settings)

    events = [it for it in items if it.type == UnifiedItemType.event]
    non_events = [it for it in items if it.type != UnifiedItemType.event]

    proposals: List[Proposal] = []
    proposals.extend(generate_create_reminder_proposals(non_events, now))
    proposals.extend(generate_follow_up_proposals(non_events, now, cfg))
    proposals.extend(generate_schedule_timeblock_proposals(non_events, events, now, cfg))
    return proposals


def maybe_adjust_followup_days_on_feedback(
    settings: Dict[str, Any],
    event_type: str,
) -> Optional[Dict[str, Any]]:
    """
    Tiny personalization loop:
    - Many dismisses → increase follow-up delay (less intrusive).
    - Accepts → decrease slightly (more proactive).
    """
    policy = resolve_support_policy(settings)
    if not adaptation_allowed(policy):
        return None

    current = settings.get("assistant.follow_up_days", 3)
    try:
        current = int(current)
    except Exception:
        current = 3

    if event_type == "dismiss":
        new = current + 1
    elif event_type == "accept":
        new = current - 1
    else:
        return None

    new = clamp_follow_up_days(new, policy)
    if new == current:
        return None
    return {"assistant.follow_up_days": new}
