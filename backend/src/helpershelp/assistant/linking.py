from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import List, Optional, Tuple

from helpershelp.assistant.models import EdgeType, ItemEdge, UnifiedItem, UnifiedItemType
from helpershelp.assistant.time_utils import utcnow


def _tokenize(text: str) -> set[str]:
    text = (text or "").lower()
    text = re.sub(r"[^a-z0-9åäö]+", " ", text)
    parts = [p for p in text.split() if len(p) >= 3]
    return set(parts)


def _jaccard(a: str, b: str) -> float:
    ta = _tokenize(a)
    tb = _tokenize(b)
    if not ta or not tb:
        return 0.0
    inter = len(ta & tb)
    union = len(ta | tb)
    return inter / union if union else 0.0


def _people_addresses(item: UnifiedItem) -> set[str]:
    return {p.address.lower() for p in (item.people or []) if p.address}


def link_emails_to_events(
    items: List[UnifiedItem],
    now: Optional[datetime] = None,
    days_window: int = 7,
    similarity_threshold: float = 0.35,
) -> List[ItemEdge]:
    """
    Minimal context linking:
    - Link email ↔ event if they share a person address and are time-near.
    - Otherwise link if title similarity crosses a threshold (fallback Jaccard).
    """
    now = now or utcnow()
    emails = [it for it in items if it.type == UnifiedItemType.email]
    events = [it for it in items if it.type == UnifiedItemType.event]

    edges: List[ItemEdge] = []
    for em in emails:
        em_people = _people_addresses(em)
        em_created = em.created_at
        for ev in events:
            if not ev.start_at:
                continue
            if abs((ev.start_at - em_created).days) > days_window:
                continue
            ev_people = _people_addresses(ev)

            reasons: List[str] = []
            score = 0.0

            if em_people and ev_people and (em_people & ev_people):
                score = 0.8
                reasons.append("shared_person")

            if score == 0.0:
                sim = _jaccard(em.title or "", ev.title or "")
                if sim >= similarity_threshold:
                    score = sim
                    reasons.append(f"title_similarity:{sim:.2f}")

            if score <= 0.0:
                continue

            edges.append(
                ItemEdge(
                    from_item_id=em.id,
                    to_item_id=ev.id,
                    edge_type=EdgeType.related_to,
                    score=float(score),
                    reasons=reasons,
                )
            )
    return edges
