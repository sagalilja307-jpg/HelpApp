from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

import requests

from helpershelp.assistant.models import ExternalRef, Person, Provenance, UnifiedItem, UnifiedItemType
from helpershelp.assistant.time_utils import utcnow


def _parse_dt(obj: Dict[str, Any]) -> Optional[datetime]:
    if not obj:
        return None
    if "dateTime" in obj and obj["dateTime"]:
        try:
            return datetime.fromisoformat(obj["dateTime"].replace("Z", "+00:00")).astimezone(timezone.utc).replace(tzinfo=None)
        except Exception:
            return None
    if "date" in obj and obj["date"]:
        try:
            # all-day: treat as midnight UTC
            return datetime.fromisoformat(obj["date"]).replace(tzinfo=None)
        except Exception:
            return None
    return None


@dataclass(frozen=True)
class GCalSyncResult:
    fetched: int
    inserted: int
    updated: int


class GCalAdapter:
    BASE = "https://www.googleapis.com/calendar/v3"

    def __init__(self, access_token: str):
        self.access_token = access_token

    def _get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        resp = requests.get(
            f"{self.BASE}{path}",
            params=params or {},
            headers={"Authorization": f"Bearer {self.access_token}"},
            timeout=20,
        )
        resp.raise_for_status()
        return resp.json()

    def fetch_items(
        self,
        days_forward: int = 14,
        days_back: int = 7,
        max_results: int = 250,
        calendar_id: str = "primary",
    ) -> List[UnifiedItem]:
        now = datetime.now(timezone.utc)
        time_min = (now - timedelta(days=int(days_back))).isoformat().replace("+00:00", "Z")
        time_max = (now + timedelta(days=int(days_forward))).isoformat().replace("+00:00", "Z")

        data = self._get(
            f"/calendars/{calendar_id}/events",
            params={
                "singleEvents": "true",
                "orderBy": "startTime",
                "timeMin": time_min,
                "timeMax": time_max,
                "maxResults": int(max_results),
            },
        )
        events = data.get("items") or []
        items: List[UnifiedItem] = []
        for ev in events:
            ev_id = ev.get("id")
            if not ev_id:
                continue

            start_at = _parse_dt(ev.get("start") or {})
            end_at = _parse_dt(ev.get("end") or {})

            attendees = ev.get("attendees") or []
            people: List[Person] = []
            for a in attendees:
                email = a.get("email")
                if not email:
                    continue
                people.append(Person(name=a.get("displayName"), address=email))

            created_at = None
            updated_at = None
            if ev.get("created"):
                try:
                    created_at = datetime.fromisoformat(ev["created"].replace("Z", "+00:00")).astimezone(timezone.utc).replace(tzinfo=None)
                except Exception:
                    created_at = None
            if ev.get("updated"):
                try:
                    updated_at = datetime.fromisoformat(ev["updated"].replace("Z", "+00:00")).astimezone(timezone.utc).replace(tzinfo=None)
                except Exception:
                    updated_at = None

            item = UnifiedItem(
                source="gcal",
                type=UnifiedItemType.event,
                title=(ev.get("summary") or "") or "",
                body=(ev.get("description") or "") or "",
                created_at=created_at or utcnow(),
                updated_at=updated_at or utcnow(),
                start_at=start_at,
                end_at=end_at,
                people=people,
                status={
                    "event": {
                        "location": ev.get("location"),
                        "calendar_id": calendar_id,
                        "htmlLink": ev.get("htmlLink"),
                    }
                },
                external_ref=ExternalRef(
                    provider="gcal",
                    provider_id=ev_id,
                    url=ev.get("htmlLink"),
                ),
                provenance=Provenance(method="gcal_pull_v1", confidence=1.0),
            )
            items.append(item)
        return items
