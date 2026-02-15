"""Domain rules for scoring items by importance"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from helpershelp.domain.models import UnifiedItem, UnifiedItemType
from helpershelp.domain.value_objects.time_utils import utcnow


@dataclass(frozen=True)
class ScoredItem:
    item: UnifiedItem
    score: float
    reasons: List[str]


def _age_days(dt: Optional[datetime], now: datetime) -> Optional[float]:
    if not dt:
        return None
    delta = now - dt
    return delta.total_seconds() / 86400.0


def _minutes_until(dt: Optional[datetime], now: datetime) -> Optional[float]:
    if not dt:
        return None
    delta = dt - now
    return delta.total_seconds() / 60.0


def score_item(item: UnifiedItem, now: datetime) -> ScoredItem:
    score = 0.0
    reasons: List[str] = []

    # Normalize to naive UTC if needed
    if now.tzinfo is not None:
        now = now.astimezone(timezone.utc).replace(tzinfo=None)

    if item.type == UnifiedItemType.event:
        mins = _minutes_until(item.start_at, now)
        if mins is not None:
            if mins < -60:
                score += 0.1
                reasons.append("event_in_past")
            elif mins <= 120:
                score += 0.95
                reasons.append("event_soon")
            elif mins <= 24 * 60:
                score += 0.65
                reasons.append("event_today")
            elif mins <= 3 * 24 * 60:
                score += 0.4
                reasons.append("event_next_3_days")
            else:
                score += 0.15
                reasons.append("event_later")

    elif item.type in (UnifiedItemType.task, UnifiedItemType.reminder):
        mins = _minutes_until(item.due_at, now)
        if mins is not None:
            if mins < 0:
                score += 0.95
                reasons.append("overdue")
            elif mins <= 8 * 60:
                score += 0.9
                reasons.append("due_today")
            elif mins <= 3 * 24 * 60:
                score += 0.7
                reasons.append("due_soon")
            elif mins <= 7 * 24 * 60:
                score += 0.45
                reasons.append("due_this_week")
            else:
                score += 0.2
                reasons.append("due_later")
        else:
            score += 0.25
            reasons.append("no_due_date")

        status = item.status or {}
        if status.get("state") == "done" or status.get("completed") is True:
            score -= 0.8
            reasons.append("completed")

    elif item.type == UnifiedItemType.email:
        status = item.status or {}
        email_status = status.get("email", status)
        direction = (email_status.get("direction") or "").lower()
        is_replied = email_status.get("is_replied")
        received_at = item.created_at

        if direction == "inbound":
            score += 0.25
            reasons.append("inbound_email")

            if is_replied is False:
                score += 0.45
                reasons.append("unreplied")
            elif is_replied is None:
                score += 0.15
                reasons.append("reply_unknown")

            age = _age_days(received_at, now)
            if age is not None:
                if age >= 7:
                    score += 0.35
                    reasons.append("old_email_7d")
                elif age >= 3:
                    score += 0.2
                    reasons.append("old_email_3d")

            subj = (item.title or "").lower()
            if "urgent" in subj or "asap" in subj:
                score += 0.15
                reasons.append("urgent_keyword")
            if "?" in (item.title or "") or "?" in (item.body or ""):
                score += 0.1
                reasons.append("question_mark")
        else:
            score += 0.05
            reasons.append("non_inbound_email")

    elif item.type == UnifiedItemType.note:
        score += 0.1
        reasons.append("note")

    # Clamp
    score = max(0.0, min(1.0, float(score)))
    return ScoredItem(item=item, score=score, reasons=reasons)


def dedupe_scored_items(scored: List[ScoredItem]) -> List[ScoredItem]:
    """
    Best-effort dedupe:
    - Emails: keep best per thread_id if present.
    - Others: keep all.
    """
    best_by_thread: Dict[str, ScoredItem] = {}
    out: List[ScoredItem] = []

    for s in scored:
        if s.item.type != UnifiedItemType.email:
            out.append(s)
            continue

        thread_id = None
        status = s.item.status or {}
        email_status = status.get("email", status)
        thread_id = email_status.get("thread_id")
        if not thread_id:
            out.append(s)
            continue

        existing = best_by_thread.get(thread_id)
        if not existing or s.score > existing.score:
            best_by_thread[thread_id] = s

    out.extend(best_by_thread.values())
    out.sort(key=lambda x: x.score, reverse=True)
    return out


def build_dashboard_lists(
    items: List[UnifiedItem],
    now: Optional[datetime] = None,
    important_limit: int = 3,
    upcoming_limit: int = 20,
) -> Tuple[List[UnifiedItem], List[UnifiedItem], List[ScoredItem]]:
    now = now or utcnow()
    scored = [score_item(it, now) for it in items]
    scored = dedupe_scored_items(scored)
    important = [s.item for s in scored[:important_limit]]
    upcoming = [s.item for s in scored[important_limit:important_limit + upcoming_limit]]
    return important, upcoming, scored
