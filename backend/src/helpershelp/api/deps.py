from __future__ import annotations

from datetime import datetime, timedelta
from typing import List, Optional

from helpershelp.application.analytics.analysis_service import AnalysisService
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, get_store
from helpershelp.application.query.query_orchestrator import QueryOrchestrator
from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.infrastructure.llm.bge_m3_adapter import get_embedding_service
from helpershelp.application.llm.llm_service import get_query_service
from helpershelp.application.llm.text_generation_service import get_text_generation_service
from helpershelp.application.mail.mail_query_service import MailQueryService
from helpershelp.infrastructure.security.oauth_adapter import OAuthService
from helpershelp.mail.provider import mail_provider
from helpershelp.retrieval.content_object import ContentObject, MailSender

mail_queries = MailQueryService(mail_provider)
oauth_service = OAuthService()
embedding_service = get_embedding_service()
text_service = get_text_generation_service()
query_service = get_query_service()

assistant_store: Optional[SqliteStore] = None


def get_assistant_store() -> SqliteStore:
    global assistant_store
    if assistant_store is None:
        assistant_store = get_store()
    return assistant_store


def reset_assistant_store() -> None:
    global assistant_store
    assistant_store = None


def assistant_store_fetch(
    time_range: Optional[dict] = None,
    data_filter: Optional[dict] = None,
) -> List[ContentObject]:
    store = get_assistant_store()

    requested_days = 90
    if time_range and isinstance(time_range, dict):
        try:
            requested_days = int(time_range.get("days") or requested_days)
        except Exception:
            requested_days = 90
    requested_days = max(1, min(3650, requested_days))

    since = utcnow() - timedelta(days=requested_days)
    items = store.list_items(since=since, limit=5000)

    allowed_types = None
    if data_filter and isinstance(data_filter, dict):
        applies_to = data_filter.get("appliesTo")
        if isinstance(applies_to, list) and applies_to:
            allowed_types = {str(item_type).lower() for item_type in applies_to if item_type}

    explicit_source_map = {
        "email": "email",
        "gmail": "email",
        "mail": "email",
        "calendar": "calendar",
        "event": "calendar",
        "events": "calendar",
        "reminder": "reminders",
        "reminders": "reminders",
        "note": "notes",
        "notes": "notes",
        "task": "tasks",
        "tasks": "tasks",
        "contact": "contacts",
        "contacts": "contacts",
        "photo": "photos",
        "photos": "photos",
        "file": "files",
        "files": "files",
        "location": "locations",
        "locations": "locations",
    }

    def map_source(source_value: str, type_value: str) -> str:
        normalized_source = (source_value or "").strip().lower()
        if normalized_source in explicit_source_map:
            return explicit_source_map[normalized_source]

        normalized_type = (type_value or "").strip().lower()
        if normalized_type in explicit_source_map:
            return explicit_source_map[normalized_type]

        if normalized_type == "event":
            return "calendar"
        if normalized_type == "location":
            return "locations"
        return "raw"

    def snippet(text: str, max_len: int = 280) -> str:
        stripped = (text or "").strip()
        if len(stripped) <= max_len:
            return stripped
        return stripped[: max(0, max_len - 1)].rstrip() + "…"

    out: List[ContentObject] = []
    location_retention_cutoff = utcnow() - timedelta(days=7)
    for item in items:
        type_value = getattr(getattr(item, "type", None), "value", None) or str(
            getattr(item, "type", "") or ""
        )
        source_value = str(getattr(item, "source", "") or "")
        mapped_source = map_source(source_value, type_value)

        if allowed_types is not None and mapped_source not in allowed_types:
            continue

        title = (getattr(item, "title", "") or "").strip() or "(Utan titel)"
        base_body = (getattr(item, "body", "") or "").strip()

        dt = (
            getattr(item, "start_at", None)
            or getattr(item, "due_at", None)
            or getattr(item, "updated_at", None)
            or getattr(item, "created_at", None)
        )
        if mapped_source == "locations" and dt and dt < location_retention_cutoff:
            continue

        hints: List[str] = []
        if mapped_source == "calendar":
            if getattr(item, "start_at", None):
                hints.append(f"Start: {getattr(item, 'start_at').isoformat()}")
            if getattr(item, "end_at", None):
                hints.append(f"End: {getattr(item, 'end_at').isoformat()}")
            event_status = (getattr(item, "status", {}) or {}).get("event") or {}
            if isinstance(event_status, dict):
                location = event_status.get("location") or ""
                if location:
                    hints.append(f"Location: {location}")
                cal_title = event_status.get("calendar_title") or event_status.get(
                    "calendar_id"
                )
                if cal_title:
                    hints.append(f"Calendar: {cal_title}")
        elif mapped_source in {"reminders", "tasks"} and getattr(item, "due_at", None):
            hints.append(f"Due: {getattr(item, 'due_at').isoformat()}")

        body_parts = [part for part in [base_body, "\n".join(hints).strip()] if part]
        body = snippet("\n".join(body_parts).strip())

        sender = MailSender(address="unknown", name=None, domain=None)
        thread_id = None
        is_replied = False

        if mapped_source == "email":
            people = getattr(item, "people", None) or []
            if people:
                first = people[0]
                address = getattr(first, "address", None) or "unknown"
                name = getattr(first, "name", None)
                domain = address.split("@")[-1] if "@" in address else None
                sender = MailSender(address=address, name=name, domain=domain)

            email_status = (getattr(item, "status", {}) or {}).get("email") or {}
            if isinstance(email_status, dict):
                thread_id = email_status.get("thread_id") or email_status.get("threadId")
                replied = email_status.get("is_replied")
                if replied is not None:
                    is_replied = bool(replied)

        out.append(
            ContentObject(
                id=str(getattr(item, "id", "")),
                source=mapped_source,
                subject=title,
                body=body,
                sender=sender,
                received_at=dt or utcnow(),
                thread_id=thread_id,
                is_replied=is_replied,
            )
        )

    return out


def parse_optional_datetime(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def get_query_orchestrator() -> QueryOrchestrator:
    analysis_service = AnalysisService(text_service=text_service)
    return QueryOrchestrator(
        query_service=query_service,
        text_service=text_service,
        analysis_service=analysis_service,
        assistant_store_getter=get_assistant_store,
        assistant_store_fetcher=assistant_store_fetch,
        mail_fetcher=mail_queries.fetch,
    )
