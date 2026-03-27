from __future__ import annotations

from dataclasses import dataclass
import logging
import re
from collections import Counter
from typing import Dict, List

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field, field_validator

from helpershelp.core.config import OLLAMA_EMBED_MODEL
from helpershelp.core.logging_config import build_log_extra
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


@dataclass(frozen=True)
class _SignalRule:
    label: str
    keywords: tuple[str, ...]
    base_confidence: float
    bonus_per_extra_match: float = 0.03


COGNITIVE_SIGNAL_PRIORITY = [
    "decision",
    "idea",
    "reflection",
    "risk",
    "question",
    "insight",
]
DOMAIN_SIGNAL_PRIORITY = [
    "work",
    "relationship",
    "health",
    "finance",
    "logistics",
    "place",
    "learning",
    "project",
    "self",
]
ACTION_SIGNAL_PRIORITY = [
    "question",
    "done",
    "todo",
    "decide",
    "plan",
    "observe",
    "schedule",
]
TIME_SIGNAL_PRIORITY = [
    "explicitDate",
    "recurring",
    "relativeTime",
    "future",
    "past",
    "present",
    "timeless",
]

COGNITIVE_SIGNAL_RULES: tuple[_SignalRule, ...] = (
    _SignalRule(
        label="decision",
        keywords=("beslut", "bestäm", "bestam", "decide", "decision", "choose", "välj", "valj"),
        base_confidence=0.9,
    ),
    _SignalRule(
        label="idea",
        keywords=("idé", "ide", "idea", "förslag", "forslag", "proposal", "brainstorm"),
        base_confidence=0.9,
    ),
    _SignalRule(
        label="reflection",
        keywords=(
            "reflektion",
            "reflection",
            "insåg",
            "insag",
            "kände",
            "kande",
            "märkte",
            "markte",
            "lärde",
            "larde",
            "noticed",
            "realized",
        ),
        base_confidence=0.9,
    ),
    _SignalRule(
        label="risk",
        keywords=("problem", "risk", "issue", "blocker", "oro", "worry", "hot", "threat"),
        base_confidence=0.88,
    ),
    _SignalRule(
        label="question",
        keywords=("undrar", "fråga", "fraga", "question", "what", "how", "why", "when"),
        base_confidence=0.83,
    ),
    _SignalRule(
        label="insight",
        keywords=("insikt", "insight", "förstod", "forstod", "slutsats", "conclusion", "aha"),
        base_confidence=0.88,
    ),
)
DOMAIN_SIGNAL_RULES: tuple[_SignalRule, ...] = (
    _SignalRule(
        label="work",
        keywords=(
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
        ),
        base_confidence=0.88,
    ),
    _SignalRule(
        label="relationship",
        keywords=(
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
            "pojkvan",
            "flickvän",
            "flickvan",
            "wife",
            "husband",
            "barn",
        ),
        base_confidence=0.86,
    ),
    _SignalRule(
        label="health",
        keywords=(
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
            "läkare",
            "lakare",
            "doctor",
            "vård",
            "vard",
            "tandläkare",
            "tandlakare",
            "dentist",
        ),
        base_confidence=0.88,
    ),
    _SignalRule(
        label="finance",
        keywords=(
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
        ),
        base_confidence=0.87,
    ),
    _SignalRule(
        label="logistics",
        keywords=(
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
        ),
        base_confidence=0.82,
    ),
    _SignalRule(
        label="place",
        keywords=("plats", "place", "hemma", "home", "kontor", "office", "adress", "address", "stad", "city", "location"),
        base_confidence=0.82,
    ),
    _SignalRule(
        label="learning",
        keywords=("lära", "lara", "lärde", "larde", "learning", "studera", "study", "kurs", "course", "bok", "read"),
        base_confidence=0.84,
    ),
    _SignalRule(
        label="project",
        keywords=("projekt", "projektet", "project", "feature", "release", "roadmap", "milestone", "implementera", "implementation"),
        base_confidence=0.88,
    ),
    _SignalRule(
        label="self",
        keywords=("mål", "mal", "value", "värdering", "vardering", "identitet", "identity", "självbild", "sjalvbild"),
        base_confidence=0.78,
    ),
)
ACTION_SIGNAL_RULES: tuple[_SignalRule, ...] = (
    _SignalRule(
        label="question",
        keywords=("undrar", "fråga", "fraga", "question", "what", "how", "why", "when"),
        base_confidence=0.84,
    ),
    _SignalRule(
        label="done",
        keywords=("klart", "färdig", "fardig", "har gjort", "gjorde", "done", "completed", "slutförd", "slutford"),
        base_confidence=0.92,
    ),
    _SignalRule(
        label="todo",
        keywords=("ska", "måste", "maste", "behöver", "behover", "todo", "to do", "att göra", "att gora", "needs to"),
        base_confidence=0.9,
    ),
    _SignalRule(
        label="decide",
        keywords=("bestäm", "bestam", "decide", "välja", "valja", "choose", "avgöra", "avgora"),
        base_confidence=0.86,
    ),
    _SignalRule(
        label="plan",
        keywords=("plan", "planera", "planerar", "överväg", "overvag", "consider", "upcoming"),
        base_confidence=0.78,
    ),
    _SignalRule(
        label="observe",
        keywords=("notering", "noterar", "observera", "observe", "noticed", "ser att", "jag ser"),
        base_confidence=0.76,
    ),
    _SignalRule(
        label="schedule",
        keywords=("boka", "book", "omboka", "reschedule", "schemalägg", "schemalagg", "schedule", "lägg in", "lagg in"),
        base_confidence=0.71,
    ),
)
RECURRING_TIME_TERMS = (
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
)
FUTURE_RELATIVE_TIME_TERMS = (
    "imorgon",
    "snart",
    "denna vecka",
    "nästa vecka",
    "nasta vecka",
    "this week",
    "next week",
    "today",
    "tomorrow",
)
PAST_RELATIVE_TIME_TERMS = (
    "igår",
    "igar",
    "förra veckan",
    "forra veckan",
    "last week",
    "yesterday",
)
PRESENT_RELATIVE_TIME_TERMS = (
    "idag",
    "this week",
    "denna vecka",
    "just nu",
    "currently",
    "today",
)
FUTURE_TIME_TERMS = ("ska", "kommer", "planerar", "framtid", "future", "upcoming", "next")
PAST_TIME_TERMS = ("gjorde", "har gjort", "tidigare", "förra", "forra", "past", "previously", "was")
PRESENT_TIME_TERMS = ("nu", "just nu", "present", "currently", "idag")
TIMELESS_TIME_TERMS = ("alltid", "generellt", "brukar", "typically", "in general")

LEGACY_ACTION_SIGNAL_MAP = {
    "schedule": "todo",
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
    cognitiveSignals: List["ProcessMemorySignal"] = Field(default_factory=list)
    domainSignals: List["ProcessMemorySignal"] = Field(default_factory=list)
    actionSignals: List["ProcessMemorySignal"] = Field(default_factory=list)
    timeSignals: List["ProcessMemorySignal"] = Field(default_factory=list)
    cognitiveType: str
    domain: str
    actionState: str
    timeRelation: str
    tags: List[str]
    embedding: List[float]


class ProcessMemorySignal(BaseModel):
    label: str = Field(..., min_length=1)
    confidence: float = Field(..., ge=0.0, le=1.0)


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


def _count_matches(text: str, keywords: tuple[str, ...]) -> int:
    match_count = 0
    for keyword in keywords:
        pattern = r"(?<!\w)" + re.escape(keyword.strip()) + r"(?!\w)"
        if re.search(pattern, text):
            match_count += 1
    return match_count


def _bounded_confidence(value: float) -> float:
    return round(max(0.0, min(1.0, value)), 2)


def _confidence_for_match(base_confidence: float, match_count: int, bonus_per_extra_match: float = 0.03) -> float:
    return _bounded_confidence(base_confidence + max(0, match_count - 1) * bonus_per_extra_match)


def _set_signal(signal_scores: Dict[str, float], *, label: str, confidence: float) -> None:
    signal_scores[label] = max(signal_scores.get(label, 0.0), _bounded_confidence(confidence))


def _signals_from_scores(signal_scores: Dict[str, float], priority: List[str]) -> List[ProcessMemorySignal]:
    if not signal_scores:
        return []

    priority_index = {label: index for index, label in enumerate(priority)}
    ordered = sorted(
        signal_scores.items(),
        key=lambda item: (-item[1], priority_index.get(item[0], len(priority_index)), item[0]),
    )
    return [ProcessMemorySignal(label=label, confidence=confidence) for label, confidence in ordered]


def _extract_rule_based_signals(clean_text: str, rules: tuple[_SignalRule, ...], priority: List[str]) -> List[ProcessMemorySignal]:
    lower = clean_text.lower()
    signal_scores: Dict[str, float] = {}
    for rule in rules:
        match_count = _count_matches(lower, rule.keywords)
        if match_count <= 0:
            continue
        _set_signal(
            signal_scores,
            label=rule.label,
            confidence=_confidence_for_match(rule.base_confidence, match_count, rule.bonus_per_extra_match),
        )
    return _signals_from_scores(signal_scores, priority)


def _cognitive_signals(clean_text: str) -> List[ProcessMemorySignal]:
    signals = _extract_rule_based_signals(clean_text, COGNITIVE_SIGNAL_RULES, COGNITIVE_SIGNAL_PRIORITY)
    if "?" in clean_text:
        signal_scores = {signal.label: signal.confidence for signal in signals}
        _set_signal(signal_scores, label="question", confidence=0.96)
        return _signals_from_scores(signal_scores, COGNITIVE_SIGNAL_PRIORITY)
    return signals


def _domain_signals(clean_text: str) -> List[ProcessMemorySignal]:
    return _extract_rule_based_signals(clean_text, DOMAIN_SIGNAL_RULES, DOMAIN_SIGNAL_PRIORITY)


def _action_signals(clean_text: str) -> List[ProcessMemorySignal]:
    signals = _extract_rule_based_signals(clean_text, ACTION_SIGNAL_RULES, ACTION_SIGNAL_PRIORITY)
    signal_scores = {signal.label: signal.confidence for signal in signals}
    if "?" in clean_text:
        _set_signal(signal_scores, label="question", confidence=0.96)
    return _signals_from_scores(signal_scores, ACTION_SIGNAL_PRIORITY)


def _time_signals(clean_text: str) -> List[ProcessMemorySignal]:
    lower = clean_text.lower()
    signal_scores: Dict[str, float] = {}

    if _has_explicit_date(lower):
        _set_signal(signal_scores, label="explicitDate", confidence=0.97)

    recurring_matches = _count_matches(lower, RECURRING_TIME_TERMS)
    if recurring_matches:
        _set_signal(signal_scores, label="recurring", confidence=_confidence_for_match(0.95, recurring_matches))

    future_relative_matches = _count_matches(lower, FUTURE_RELATIVE_TIME_TERMS)
    past_relative_matches = _count_matches(lower, PAST_RELATIVE_TIME_TERMS)
    present_relative_matches = _count_matches(lower, PRESENT_RELATIVE_TIME_TERMS)
    total_relative_matches = future_relative_matches + past_relative_matches + present_relative_matches
    if total_relative_matches:
        _set_signal(signal_scores, label="relativeTime", confidence=_confidence_for_match(0.94, total_relative_matches))

    if future_relative_matches:
        _set_signal(signal_scores, label="future", confidence=_confidence_for_match(0.8, future_relative_matches))
    if past_relative_matches:
        _set_signal(signal_scores, label="past", confidence=_confidence_for_match(0.8, past_relative_matches))
    if present_relative_matches:
        _set_signal(signal_scores, label="present", confidence=_confidence_for_match(0.8, present_relative_matches))

    future_matches = _count_matches(lower, FUTURE_TIME_TERMS)
    if future_matches:
        _set_signal(signal_scores, label="future", confidence=_confidence_for_match(0.78, future_matches))

    past_matches = _count_matches(lower, PAST_TIME_TERMS)
    if past_matches:
        _set_signal(signal_scores, label="past", confidence=_confidence_for_match(0.78, past_matches))

    present_matches = _count_matches(lower, PRESENT_TIME_TERMS)
    if present_matches:
        _set_signal(signal_scores, label="present", confidence=_confidence_for_match(0.77, present_matches))

    timeless_matches = _count_matches(lower, TIMELESS_TIME_TERMS)
    if timeless_matches:
        _set_signal(signal_scores, label="timeless", confidence=_confidence_for_match(0.84, timeless_matches))

    return _signals_from_scores(signal_scores, TIME_SIGNAL_PRIORITY)


def _legacy_label_from_signals(
    signals: List[ProcessMemorySignal],
    *,
    priority: List[str],
    default_label: str,
    compatibility_map: Dict[str, str] | None = None,
) -> str:
    if not signals:
        return default_label

    legacy_scores: Dict[str, float] = {}
    for signal in signals:
        legacy_label = compatibility_map.get(signal.label, signal.label) if compatibility_map else signal.label
        if not legacy_label:
            continue
        _set_signal(legacy_scores, label=legacy_label, confidence=signal.confidence)

    legacy_signals = _signals_from_scores(legacy_scores, priority)
    if not legacy_signals:
        return default_label
    return legacy_signals[0].label


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
            extra=build_log_extra(
                route=route,
                lang=request.language,
                tz=timezone_name,
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
                reason="config_model",
            ),
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
            extra=build_log_extra(
                route=route,
                lang=request.language,
                tz=timezone_name,
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
                reason="runtime_status",
                exc_type=exc.__class__.__name__,
            ),
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
            extra=build_log_extra(
                route=route,
                lang=request.language,
                tz=timezone_name,
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
                reason="runtime_model",
            ),
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
            extra=build_log_extra(
                route=route,
                lang=request.language,
                tz=timezone_name,
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
                reason="model_unavailable",
            ),
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding service unavailable",
        )

    clean_text = _clean_text(request.text)
    cognitive_signals = _cognitive_signals(clean_text)
    domain_signals = _domain_signals(clean_text)
    action_signals = _action_signals(clean_text)
    time_signals = _time_signals(clean_text)
    cognitive_type = _legacy_label_from_signals(
        cognitive_signals,
        priority=COGNITIVE_SIGNAL_PRIORITY,
        default_label="other",
    )
    domain = _legacy_label_from_signals(
        domain_signals,
        priority=DOMAIN_SIGNAL_PRIORITY,
        default_label="other",
    )
    action_state = _legacy_label_from_signals(
        action_signals,
        priority=ACTION_SIGNAL_PRIORITY,
        default_label="info",
        compatibility_map=LEGACY_ACTION_SIGNAL_MAP,
    )
    time_relation = _legacy_label_from_signals(
        time_signals,
        priority=TIME_SIGNAL_PRIORITY,
        default_label="none",
    )
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
            extra=build_log_extra(
                route=route,
                lang=request.language,
                tz=timezone_name,
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
                reason="embed_backend",
                exc_type=exc.__class__.__name__,
            ),
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
            extra=build_log_extra(
                route=route,
                lang=request.language,
                tz=timezone_name,
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
                reason="empty_vector",
            ),
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
        extra=build_log_extra(
            route=route,
            lang=request.language,
            tz=timezone_name,
            status=status.HTTP_200_OK,
        ),
    )

    return ProcessMemoryResponse(
        cleanText=clean_text,
        cognitiveSignals=cognitive_signals,
        domainSignals=domain_signals,
        actionSignals=action_signals,
        timeSignals=time_signals,
        cognitiveType=cognitive_type,
        domain=domain,
        actionState=action_state,
        timeRelation=time_relation,
        tags=tags,
        embedding=[float(value) for value in vectors[0]],
    )
