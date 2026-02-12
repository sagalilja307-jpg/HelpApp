from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, time, timezone
from typing import List, Optional, Tuple

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType


@dataclass(frozen=True)
class TimeSlot:
    start_at: datetime
    end_at: datetime


def _as_utc_naive(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def _overlaps(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime) -> bool:
    return a_start < b_end and b_start < a_end


def list_busy_intervals(events: List[UnifiedItem], window_start: datetime, window_end: datetime) -> List[TimeSlot]:
    busy: List[TimeSlot] = []
    for ev in events:
        if ev.type != UnifiedItemType.event:
            continue
        if not ev.start_at or not ev.end_at:
            continue
        s = _as_utc_naive(ev.start_at)
        e = _as_utc_naive(ev.end_at)
        if e <= window_start or s >= window_end:
            continue
        busy.append(TimeSlot(start_at=max(s, window_start), end_at=min(e, window_end)))
    busy.sort(key=lambda x: x.start_at)
    # merge
    merged: List[TimeSlot] = []
    for slot in busy:
        if not merged or slot.start_at > merged[-1].end_at:
            merged.append(slot)
        else:
            merged[-1] = TimeSlot(start_at=merged[-1].start_at, end_at=max(merged[-1].end_at, slot.end_at))
    return merged


def suggest_free_slots(
    events: List[UnifiedItem],
    now: datetime,
    latest_end: datetime,
    duration_minutes: int = 120,
    workday_start: int = 9,
    workday_end: int = 17,
    max_slots: int = 2,
) -> List[TimeSlot]:
    """
    Best-effort timeblock suggestion:
    - Searches from now to latest_end.
    - Only returns slots fully within work hours (UTC-naive hours).
    - Avoids overlapping existing events.
    """
    if duration_minutes <= 0:
        return []
    now = _as_utc_naive(now)
    latest_end = _as_utc_naive(latest_end)
    if latest_end <= now:
        return []

    busy = list_busy_intervals(events, now, latest_end)
    duration = timedelta(minutes=duration_minutes)

    slots: List[TimeSlot] = []
    cursor = now

    def work_bounds(day: datetime) -> Tuple[datetime, datetime]:
        start = datetime.combine(day.date(), time(hour=workday_start))
        end = datetime.combine(day.date(), time(hour=workday_end))
        return start, end

    while cursor + duration <= latest_end and len(slots) < max_slots:
        day_start, day_end = work_bounds(cursor)
        if cursor < day_start:
            cursor = day_start

        if cursor + duration > day_end:
            cursor = datetime.combine((cursor + timedelta(days=1)).date(), time(hour=workday_start))
            continue

        candidate = TimeSlot(start_at=cursor, end_at=cursor + duration)
        conflict = False
        for b in busy:
            if _overlaps(candidate.start_at, candidate.end_at, b.start_at, b.end_at):
                cursor = max(cursor, b.end_at)
                conflict = True
                break
        if conflict:
            continue

        slots.append(candidate)
        cursor = candidate.end_at + timedelta(minutes=30)

    return slots

