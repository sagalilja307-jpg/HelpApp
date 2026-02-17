from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import requests

from helpershelp.assistant.models import ExternalRef, Person, Provenance, UnifiedItem, UnifiedItemType
from helpershelp.domain.value_objects.time_utils import utcnow


def _parse_email_address(raw: str) -> Tuple[Optional[str], str]:
    raw = (raw or "").strip()
    # Very small parser: `Name <addr@x>` or `addr@x`
    m = re.match(r"^\\s*(.*?)\\s*<([^>]+)>\\s*$", raw)
    if m:
        name = m.group(1).strip().strip('"') or None
        addr = m.group(2).strip()
        return name, addr
    return None, raw


def _ms_to_dt(ms: str) -> datetime:
    try:
        sec = int(ms) / 1000.0
    except Exception:
        sec = datetime.now(tz=timezone.utc).timestamp()
    return datetime.fromtimestamp(sec, tz=timezone.utc).replace(tzinfo=None)


@dataclass(frozen=True)
class GmailSyncResult:
    fetched: int
    inserted: int
    updated: int


class GmailAdapter:
    BASE = "https://gmail.googleapis.com/gmail/v1"

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

    def list_message_ids(self, days: int, max_results: int) -> List[Dict[str, str]]:
        q = f"newer_than:{int(days)}d"
        data = self._get("/users/me/messages", params={"q": q, "maxResults": int(max_results)})
        return data.get("messages") or []

    def get_message_metadata(self, message_id: str) -> Dict[str, Any]:
        return self._get(
            f"/users/me/messages/{message_id}",
            params={
                "format": "metadata",
                "metadataHeaders": ["From", "To", "Cc", "Bcc", "Subject", "Date", "Message-ID"],
            },
        )

    def get_thread_metadata(self, thread_id: str) -> Dict[str, Any]:
        return self._get(
            f"/users/me/threads/{thread_id}",
            params={
                "format": "metadata",
                "metadataHeaders": ["From", "To", "Subject", "Date"],
            },
        )

    @staticmethod
    def _headers_map(msg: Dict[str, Any]) -> Dict[str, str]:
        headers = (((msg.get("payload") or {}).get("headers")) or [])
        out: Dict[str, str] = {}
        for h in headers:
            name = (h.get("name") or "").lower()
            value = h.get("value") or ""
            if name:
                out[name] = value
        return out

    @staticmethod
    def _infer_direction(label_ids: List[str]) -> str:
        labels = set(label_ids or [])
        if "SENT" in labels:
            return "outbound"
        if "INBOX" in labels:
            return "inbound"
        return "unknown"

    def _infer_is_replied(
        self,
        thread_id: str,
        inbound_internal_ms: str,
    ) -> Optional[bool]:
        """
        Best-effort reply inference:
        - If the thread has any SENT message after the inbound message date → replied.
        - Otherwise → not replied.
        """
        try:
            inbound_dt = _ms_to_dt(inbound_internal_ms)
        except Exception:
            return None

        try:
            thread = self.get_thread_metadata(thread_id)
        except Exception:
            return None

        for msg in thread.get("messages") or []:
            labels = set(msg.get("labelIds") or [])
            if "SENT" not in labels:
                continue
            internal = msg.get("internalDate")
            if not internal:
                continue
            sent_dt = _ms_to_dt(internal)
            if sent_dt > inbound_dt:
                return True
        return False

    def fetch_items(self, days: int = 90, max_results: int = 50, max_threads_to_check: int = 15) -> List[UnifiedItem]:
        ids = self.list_message_ids(days=days, max_results=max_results)
        items: List[UnifiedItem] = []

        thread_checks = 0
        for row in ids:
            msg_id = row.get("id")
            if not msg_id:
                continue
            meta = self.get_message_metadata(msg_id)
            thread_id = meta.get("threadId")
            headers = self._headers_map(meta)
            subject = headers.get("subject", "") or ""
            from_raw = headers.get("from", "") or ""
            to_raw = headers.get("to", "") or ""
            name, addr = _parse_email_address(from_raw)

            label_ids = meta.get("labelIds") or []
            direction = self._infer_direction(label_ids)

            internal_ms = meta.get("internalDate") or ""
            received_at = _ms_to_dt(internal_ms) if internal_ms else utcnow()

            is_replied: Optional[bool] = None
            if direction == "inbound" and thread_id and thread_checks < max_threads_to_check:
                # Only run thread checks for older mails or mails that look like questions
                age_days = (utcnow() - received_at).total_seconds() / 86400.0
                if age_days >= 3 or "?" in subject:
                    is_replied = self._infer_is_replied(thread_id, internal_ms)
                    thread_checks += 1

            people: List[Person] = []
            if addr:
                people.append(Person(name=name, address=addr))

            item = UnifiedItem(
                source="gmail",
                type=UnifiedItemType.email,
                title=subject,
                body=(meta.get("snippet") or "") or "",
                created_at=received_at,
                updated_at=utcnow(),
                people=people,
                status={
                    "email": {
                        "thread_id": thread_id,
                        "direction": direction,
                        "is_replied": is_replied,
                        "to": to_raw,
                        "labels": label_ids,
                    }
                },
                external_ref=ExternalRef(
                    provider="gmail",
                    provider_id=msg_id,
                    url=f"https://mail.google.com/mail/u/0/#all/{thread_id or msg_id}",
                ),
                provenance=Provenance(method="gmail_pull_v1", confidence=1.0),
            )
            items.append(item)

        return items
