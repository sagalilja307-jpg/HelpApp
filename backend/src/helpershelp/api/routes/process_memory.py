from __future__ import annotations

import logging
import re
from collections import Counter
from typing import List

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field, field_validator

from helpershelp.core.config import OLLAMA_EMBED_MODEL
from helpershelp.llm import get_embedding_service

logger = logging.getLogger(__name__)
router = APIRouter()

MAX_TEXT_LENGTH = 8_000
REQUIRED_EMBED_PREFIX = "bge-m3"

_STOP_WORDS = {
    "och",
    "att",
    "det",
    "som",
    "den",
    "detta",
    "jag",
    "du",
    "vi",
    "ni",
    "är",
    "var",
    "för",
    "med",
    "till",
    "på",
    "av",
    "om",
    "in",
    "the",
    "a",
    "an",
    "to",
    "of",
    "for",
    "and",
    "is",
}


class ProcessMemoryRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=MAX_TEXT_LENGTH)
    language: str = Field(default="sv", min_length=2, max_length=8)

    @field_validator("text")
    @classmethod
    def validate_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("text must not be empty")
        return value

    @field_validator("language")
    @classmethod
    def validate_language(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not normalized:
            raise ValueError("language must not be empty")
        return normalized


class ProcessMemoryResponse(BaseModel):
    cleanText: str
    cognitiveType: str
    domain: str
    actionState: str
    timeRelation: str
    tags: List[str]
    embedding: List[float]


def _model_prefix(value: str) -> str:
    return (value or "").strip().lower().split(":")[0]


def _is_allowed_model(value: str) -> bool:
    return _model_prefix(value) == REQUIRED_EMBED_PREFIX


def _clean_text(raw: str) -> str:
    single_spaced = re.sub(r"\s+", " ", raw).strip()
    # Trim common bullet prefixes but keep semantic content.
    return re.sub(r"^[\-\*\u2022]\s*", "", single_spaced)


def _contains_any(text: str, keywords: List[str]) -> bool:
    return any(keyword in text for keyword in keywords)


def _cognitive_type(clean_text: str) -> str:
    lower = clean_text.lower()

    if _contains_any(
        lower,
        ["beslut", "bestäm", "decide", "decision", "choose", "välj"],
    ):
        return "decision"
    if _contains_any(
        lower,
        ["idé", "ide", "idea", "förslag", "proposal", "brainstorm"],
    ):
        return "idea"
    if _contains_any(
        lower,
        ["reflektion", "reflection", "insåg", "insag", "kände", "kande", "lärde", "learned"],
    ):
        return "reflection"
    if _contains_any(
        lower,
        ["problem", "risk", "issue", "blocker", "oro", "worry", "hot", "threat"],
    ):
        return "risk"
    if "?" in clean_text:
        return "question"
    if _contains_any(
        lower,
        ["insikt", "insight", "förstod", "forstod", "realized", "slutsats", "conclusion"],
    ):
        return "insight"
    return "other"


def _domain(clean_text: str) -> str:
    lower = clean_text.lower()
    domain_keywords: List[tuple[str, List[str]]] = [
        (
            "work",
            [
                "jobb",
                "arbete",
                "work",
                "kollega",
                "chef",
                "möte",
                "mote",
                "meeting",
                "kund",
                "client",
                "deadline",
                "sprint",
            ],
        ),
        (
            "relationship",
            [
                "partner",
                "vän",
                "van",
                "vänskap",
                "vanskap",
                "relation",
                "relationship",
                "familj",
                "family",
                "fyller år",
                "fyller ar",
                "birthday",
                "bday",
                "pojkvän",
                "flickvän",
                "wife",
                "husband",
                "barn",
            ],
        ),
        (
            "health",
            [
                "hälsa",
                "halsa",
                "health",
                "sömn",
                "somn",
                "träning",
                "traning",
                "workout",
                "exercise",
                "puls",
                "stress",
                "diet",
                "medicin",
            ],
        ),
        (
            "finance",
            [
                "budget",
                "ekonomi",
                "finance",
                "lön",
                "lon",
                "salary",
                "kostnad",
                "cost",
                "räkning",
                "rakning",
                "faktura",
                "invest",
                "spar",
            ],
        ),
        (
            "logistics",
            [
                "resa",
                "travel",
                "flyg",
                "flight",
                "leverans",
                "delivery",
                "paket",
                "schedule",
                "schema",
                "transport",
                "pendla",
            ],
        ),
        (
            "place",
            [
                "plats",
                "place",
                "hemma",
                "home",
                "kontor",
                "office",
                "adress",
                "address",
                "stad",
                "city",
                "location",
            ],
        ),
        (
            "learning",
            [
                "lära",
                "lara",
                "lärde",
                "larde",
                "learning",
                "studera",
                "study",
                "kurs",
                "course",
                "bok",
                "read",
            ],
        ),
        (
            "project",
            [
                "projekt",
                "project",
                "feature",
                "release",
                "roadmap",
                "milestone",
                "implementera",
                "implementation",
            ],
        ),
        (
            "self",
            [
                "jag",
                "mig",
                "myself",
                "self",
                "mål",
                "mal",
                "value",
                "värdering",
                "vardering",
                "identitet",
                "identity",
            ],
        ),
    ]

    for domain, keywords in domain_keywords:
        if _contains_any(lower, keywords):
            return domain
    return "other"


def _action_state(clean_text: str) -> str:
    lower = clean_text.lower()

    if "?" in clean_text or _contains_any(lower, ["undrar", "fråga", "fraga", "question", "what", "how"]):
        return "question"
    if _contains_any(
        lower,
        ["klart", "färdig", "fardig", "har gjort", "gjorde", "done", "completed", "slutförd", "slutford"],
    ):
        return "done"
    if _contains_any(
        lower,
        ["ska ", "måste", "maste", "behöver", "behover", "todo", "to do", "att göra", "att gora", "needs to"],
    ):
        return "todo"
    if _contains_any(
        lower,
        ["bestäm", "bestam", "decide", "välja", "valja", "choose", "avgöra", "avgora"],
    ):
        return "decide"
    if _contains_any(
        lower,
        ["plan", "planera", "planerar", "överväg", "overvag", "consider", "upcoming"],
    ):
        return "plan"
    if _contains_any(
        lower,
        ["notering", "noterar", "observera", "observe", "noticed", "ser att", "jag ser"],
    ):
        return "observe"
    return "info"


def _has_explicit_date(text: str) -> bool:
    if re.search(r"\b\d{4}-\d{2}-\d{2}\b", text):
        return True
    if re.search(r"\b\d{1,2}[./-]\d{1,2}(?:[./-]\d{2,4})?\b", text):
        return True
    if re.search(
        r"\b\d{1,2}\s+(jan|januari|feb|februari|mar|mars|apr|april|maj|jun|juni|jul|juli|aug|augusti|sep|sept|september|okt|oktober|nov|november|dec|december|january|february|march|april|may|june|july|august|september|october|november|december)\b",
        text,
    ):
        return True
    if re.search(
        r"\b(jan|januari|feb|februari|mar|mars|apr|april|maj|jun|juni|jul|juli|aug|augusti|sep|sept|september|okt|oktober|nov|november|dec|december|january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}\b",
        text,
    ):
        return True
    return False


def _time_relation(clean_text: str) -> str:
    lower = clean_text.lower()

    if _has_explicit_date(lower):
        return "explicitDate"

    if _contains_any(
        lower,
        [
            "varje dag",
            "varje vecka",
            "varje månad",
            "varje manad",
            "varje år",
            "varje ar",
            "dagligen",
            "weekly",
            "monthly",
            "yearly",
            "every day",
            "every week",
        ],
    ):
        return "recurring"

    if _contains_any(
        lower,
        [
            "idag",
            "imorgon",
            "igår",
            "igar",
            "snart",
            "denna vecka",
            "nästa vecka",
            "nasta vecka",
            "förra veckan",
            "forra veckan",
            "this week",
            "next week",
            "last week",
            "today",
            "tomorrow",
            "yesterday",
        ],
    ):
        return "relativeTime"

    if _contains_any(
        lower,
        ["ska ", "kommer", "planerar", "framtid", "future", "upcoming", "next"],
    ):
        return "future"
    if _contains_any(
        lower,
        ["gjorde", "har gjort", "tidigare", "förra", "forra", "past", "previously", "was"],
    ):
        return "past"
    if _contains_any(lower, ["nu", "just nu", "present", "currently", "idag"]):
        return "present"
    if _contains_any(lower, ["alltid", "generellt", "brukar", "typically", "in general"]):
        return "timeless"

    return "none"


def _tags(clean_text: str) -> List[str]:
    tokens = re.findall(r"[a-zA-Z0-9åäöÅÄÖ]{3,}", clean_text.lower())
    filtered = [token for token in tokens if token not in _STOP_WORDS]
    if not filtered:
        return ["memory"]
    counts = Counter(filtered)
    ranked = sorted(counts.items(), key=lambda item: (-item[1], -len(item[0]), item[0]))
    return [token for token, _ in ranked[:5]]


@router.post("/process-memory", response_model=ProcessMemoryResponse, tags=["memory"])
async def process_memory(request: ProcessMemoryRequest) -> ProcessMemoryResponse:
    route = "/process-memory"
    timezone_name = "n/a"

    configured_model = (OLLAMA_EMBED_MODEL or "").strip()
    if not _is_allowed_model(configured_model):
        logger.error(
            "Memory request route=%s lang=%s tz=%s status=%d reason=config_model",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )

    embed_service = get_embedding_service()
    try:
        runtime = embed_service.status()
    except Exception as exc:
        logger.warning(
            "Memory request route=%s lang=%s tz=%s status=%d reason=runtime_status exc_type=%s",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
            exc.__class__.__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        ) from exc
    if not _is_allowed_model(runtime.embedding_model):
        logger.error(
            "Memory request route=%s lang=%s tz=%s status=%d reason=runtime_model",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )
    if not runtime.model_available:
        logger.warning(
            "Memory request route=%s lang=%s tz=%s status=%d reason=model_unavailable",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )

    clean_text = _clean_text(request.text)
    cognitive_type = _cognitive_type(clean_text)
    domain = _domain(clean_text)
    action_state = _action_state(clean_text)
    time_relation = _time_relation(clean_text)
    tags = _tags(clean_text)

    try:
        vectors = embed_service.embed_texts([clean_text])
    except Exception as exc:
        logger.warning(
            "Memory request route=%s lang=%s tz=%s status=%d reason=embed_backend exc_type=%s",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
            exc.__class__.__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        ) from exc

    if not vectors or not vectors[0]:
        logger.error(
            "Memory request route=%s lang=%s tz=%s status=%d reason=empty_vector",
            route,
            request.language,
            timezone_name,
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )

    logger.info(
        "Memory request route=%s lang=%s tz=%s status=%d",
        route,
        request.language,
        timezone_name,
        status.HTTP_200_OK,
    )

    return ProcessMemoryResponse(
        cleanText=clean_text,
        cognitiveType=cognitive_type,
        domain=domain,
        actionState=action_state,
        timeRelation=time_relation,
        tags=tags,
        embedding=[float(value) for value in vectors[0]],
    )
