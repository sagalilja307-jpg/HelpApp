from __future__ import annotations

import re
from typing import Dict


FORBIDDEN_PHRASE_REPLACEMENTS: Dict[str, str] = {
    "du borde": "det kan vara hjälpsamt att",
    "du ligger efter": "det finns saker som riskerar att falla bort",
    "misslyckades": "blev inte klart",
    "du måste": "du kan välja att",
    "det är sent": "det är tidskritiskt",
}


def contains_forbidden_phrase(text: str) -> bool:
    lowered = (text or "").lower()
    return any(phrase in lowered for phrase in FORBIDDEN_PHRASE_REPLACEMENTS)


def enforce_neutral_language(text: str) -> str:
    result = text or ""
    for phrase, replacement in FORBIDDEN_PHRASE_REPLACEMENTS.items():
        pattern = re.compile(re.escape(phrase), flags=re.IGNORECASE)
        result = pattern.sub(replacement, result)
    return result
