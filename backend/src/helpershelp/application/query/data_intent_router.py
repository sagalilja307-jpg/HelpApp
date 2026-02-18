from __future__ import annotations

import os
import re
from datetime import datetime
from typing import Callable, Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo

from helpershelp.application.query.timeframe_resolver import QueryTimeframeResolver


class DataIntentRouter:
    _DOMAIN_KEYWORDS: Dict[str, List[str]] = {
        "calendar": [
            "calendar",
            "kalender",
            "meeting",
            "möte",
            "möten",
            "event",
            "events",
            "schedule",
            "agenda",
            "bokad",
        ],
        "reminders": [
            "reminder",
            "reminders",
            "påminnelse",
            "påminnelser",
            "task",
            "tasks",
            "todo",
            "to-do",
            "att göra",
        ],
        "mail": [
            "mail",
            "mejl",
            "email",
            "inbox",
            "gmail",
            "message",
            "messages",
            "unread",
            "oläst",
            "olästa",
        ],
        "contacts": [
            "contact",
            "contacts",
            "kontakt",
            "kontakter",
            "telefonnummer",
            "phone number",
        ],
        "photos": [
            "photo",
            "photos",
            "image",
            "images",
            "bild",
            "bilder",
            "foto",
            "foton",
        ],
        "files": [
            "file",
            "files",
            "document",
            "documents",
            "fil",
            "filer",
            "dokument",
            "pdf",
        ],
        "location": [
            "location",
            "where am i",
            "near me",
            "nearby",
            "around here",
            "var är jag",
            "var ar jag",
            "nära mig",
            "nara mig",
            "i närheten",
            "i narheten",
            "plats",
        ],
        "notes": [
            "note",
            "notes",
            "memo",
            "memos",
            "anteckning",
            "anteckningar",
        ],
    }

    _COUNT_MARKERS = [
        "how many",
        "count",
        "hur många",
        "hur manga",
        "antal",
    ]
    _NEXT_MARKERS = [
        "next",
        "nästa",
        "nasta",
        "upcoming",
        "kommande",
    ]
    _DETAILS_MARKERS = [
        "details",
        "detalj",
        "detaljer",
        "visa detaljer",
        "show details",
        "id:",
    ]
    _SEARCH_MARKERS = [
        "search",
        "find",
        "hitta",
        "sök",
        "sok",
        "leta",
    ]

    _UNREAD_MARKERS = ["unread", "oläst", "olästa"]
    _UNANSWERED_MARKERS = ["unanswered", "obesvarade", "inte svarat"]

    _ID_FILTER = re.compile(r"\b(?:id|event_id|reminder_id|message_id)\s*[:=]\s*([A-Za-z0-9:_-]+)\b", re.IGNORECASE)
    _LIMIT = re.compile(r"\b(?:top|visa|show|senaste|last)\s+(\d{1,3})\b", re.IGNORECASE)

    def __init__(
        self,
        timezone_name: Optional[str] = None,
        now_provider: Optional[Callable[[], datetime]] = None,
    ):
        configured = timezone_name or os.getenv("HELPERSHELP_TIMEZONE", "Europe/Stockholm")
        try:
            self._timezone = ZoneInfo(configured)
        except Exception:
            self._timezone = ZoneInfo("Europe/Stockholm")
        self._timeframe_resolver = QueryTimeframeResolver(
            timezone_name=self._timezone.key,
            now_provider=now_provider,
        )

    def route(self, *, query: str, language: str = "sv") -> Dict[str, object]:
        _ = language
        normalized = (query or "").strip().lower()
        timeframe = self._timeframe_resolver.resolve(normalized)
        domain, suggestions = self._resolve_domain(normalized)
        if domain is None:
            suggested_domains = suggestions or ["calendar", "mail"]
            return {
                "domain": "system",
                "operation": "needs_clarification",
                "filters": {"suggested_domains": suggested_domains},
            }

        operation = self._resolve_operation(normalized)
        filters = self._extract_filters(normalized, domain=domain, operation=operation)
        sort = self._default_sort(domain=domain, operation=operation)
        limit = self._resolve_limit(normalized, operation=operation)
        if operation in {"next", "details"}:
            limit = 1

        payload: Dict[str, object] = {
            "domain": domain,
            "operation": operation,
        }
        if timeframe is not None:
            payload["timeframe"] = timeframe
        if filters:
            payload["filters"] = filters
        if sort is not None:
            payload["sort"] = sort
        if limit is not None and operation != "count":
            payload["limit"] = limit
        return payload

    def _resolve_domain(self, normalized_query: str) -> Tuple[Optional[str], List[str]]:
        scores: Dict[str, int] = {}
        for domain, keywords in self._DOMAIN_KEYWORDS.items():
            score = 0
            for keyword in keywords:
                if keyword in normalized_query:
                    score += 1
            scores[domain] = score

        best_score = max(scores.values()) if scores else 0
        if best_score <= 0:
            return None, []

        best_domains = [domain for domain, score in scores.items() if score == best_score]
        if len(best_domains) == 1:
            return best_domains[0], best_domains

        if "calendar" in best_domains and "reminders" in best_domains:
            return "calendar", best_domains

        return None, best_domains[:2]

    def _resolve_operation(self, normalized_query: str) -> str:
        if any(marker in normalized_query for marker in self._COUNT_MARKERS):
            return "count"
        if self._ID_FILTER.search(normalized_query) or any(
            marker in normalized_query for marker in self._DETAILS_MARKERS
        ):
            return "details"
        if any(marker in normalized_query for marker in self._NEXT_MARKERS):
            return "next"
        if any(marker in normalized_query for marker in self._SEARCH_MARKERS):
            return "search"
        return "list"

    def _extract_filters(self, normalized_query: str, *, domain: str, operation: str) -> Dict[str, object]:
        filters: Dict[str, object] = {}

        id_match = self._ID_FILTER.search(normalized_query)
        if id_match:
            filters["id"] = id_match.group(1)

        if domain == "mail":
            if any(marker in normalized_query for marker in self._UNREAD_MARKERS):
                filters["status"] = "unread"
            elif any(marker in normalized_query for marker in self._UNANSWERED_MARKERS):
                filters["status"] = "unanswered"

        if "all day" in normalized_query or "heldag" in normalized_query:
            filters["is_all_day"] = True
        if "not all day" in normalized_query or "inte heldag" in normalized_query:
            filters["is_all_day"] = False

        if operation in {"search", "details"} and "id" not in filters:
            filters["query"] = normalized_query

        return filters

    def _default_sort(self, *, domain: str, operation: str) -> Optional[Dict[str, str]]:
        if operation in {"count", "needs_clarification", "details"}:
            return None

        if domain == "calendar":
            return {"field": "start_at", "direction": "asc"}
        if domain == "reminders":
            return {"field": "due_date", "direction": "asc"}
        if domain == "mail":
            return {"field": "date", "direction": "desc"}
        if domain == "photos":
            return {"field": "created_at", "direction": "desc"}
        if domain == "location":
            return {"field": "observed_at", "direction": "desc"}
        return {"field": "updated_at", "direction": "desc"}

    def _resolve_limit(self, normalized_query: str, *, operation: str) -> Optional[int]:
        if operation in {"count", "needs_clarification"}:
            return None
        match = self._LIMIT.search(normalized_query)
        if not match:
            return 20
        parsed = int(match.group(1))
        return max(1, min(200, parsed))
