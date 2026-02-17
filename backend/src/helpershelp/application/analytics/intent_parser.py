from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional


CALENDAR_SPECIFIC_DAY_INTENT = "calendar.specific_day_query"
CALENDAR_LEAST_LOADED_DAY_INTENT = "calendar.least_loaded_day"


@dataclass(frozen=True)
class ParsedIntent:
    intent_id: str


class IntentParser:
    """Deterministic parser for analytics intents (Fas 0.5)."""

    _least_loaded_patterns = [
        re.compile(r"\b(minst\s+belastad|minst\s+bokad|ledigast|minst\s+upptagen)\b", re.IGNORECASE),
        re.compile(r"\bleast\s+loaded\b", re.IGNORECASE),
    ]

    _relative_day_patterns = [
        re.compile(r"\bidag\b", re.IGNORECASE),
        re.compile(r"\bigår\b", re.IGNORECASE),
        re.compile(r"\bimorgon\b", re.IGNORECASE),
    ]

    _explicit_day_pattern = re.compile(r"\b(?:den\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", re.IGNORECASE)

    _specific_day_subject_markers = [
        "vad gör jag",
        "vad gjorde jag",
        "vad ska jag",
        "what am i doing",
        "what did i do",
    ]

    _calendar_markers = [
        "kalender",
        "möte",
        "möten",
        "bokad",
        "händelse",
        "händelser",
        "event",
        "events",
    ]

    def parse(self, query: str) -> Optional[ParsedIntent]:
        normalized = (query or "").strip().lower()
        if not normalized:
            return None

        if self._matches_least_loaded_day(normalized):
            return ParsedIntent(intent_id=CALENDAR_LEAST_LOADED_DAY_INTENT)

        if self._matches_specific_day(normalized):
            return ParsedIntent(intent_id=CALENDAR_SPECIFIC_DAY_INTENT)

        return None

    def _matches_least_loaded_day(self, normalized_query: str) -> bool:
        return any(pattern.search(normalized_query) for pattern in self._least_loaded_patterns)

    def _matches_specific_day(self, normalized_query: str) -> bool:
        has_day_reference = (
            any(pattern.search(normalized_query) for pattern in self._relative_day_patterns)
            or bool(self._explicit_day_pattern.search(normalized_query))
        )
        if not has_day_reference:
            return False

        if any(marker in normalized_query for marker in self._specific_day_subject_markers):
            return True

        return any(marker in normalized_query for marker in self._calendar_markers)
