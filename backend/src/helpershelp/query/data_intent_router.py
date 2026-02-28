"""
Deterministisk router som mappar användarfrågor till IntentPlanDTO-liknande DataIntent payload.
"""

from __future__ import annotations

from datetime import datetime
import re
from typing import Any, Callable, Dict, Optional, cast

from helpershelp.query.intent_plan import (
    Domain,
    IntentPlanDTO,
    Operation,
    TimeScopeDTO,
    TimeScopeType,
)
from helpershelp.llm import get_qwen_classifier, get_qwen_filter_structurer
from helpershelp.query.time_policy import TimePolicy, TimePolicyConfig
from helpershelp.query.timeframe_resolver import QueryTimeframeResolver, TimeIntent
from helpershelp.core.time_utils import utcnow_aware


HEALTH_DOMAIN_KEYWORDS: tuple[str, ...] = (
    "hälsa",
    "halsa",
    "health",
    "steg",
    "step",
    "steps",
    "träning",
    "traning",
    "tränat",
    "tranat",
    "tränade",
    "tranade",
    "workout",
    "exercise",
    "löpning",
    "lopning",
    "cykling",
    "cycling",
    "styrka",
    "strength",
    "sömn",
    "somn",
    "sovit",
    "sleep",
    "puls",
    "hjärtfrekvens",
    "hjartfrekvens",
    "hrv",
    "vilopuls",
    "andning",
    "respiratory",
    "blodsyre",
    "blood oxygen",
    "mindful",
    "sinnestillstånd",
    "sinnestillstand",
    "state of mind",
    "mående",
    "maende",
    "mår",
    "mar",
    "kalori",
    "kalorier",
    "calorie",
    "calories",
)

HEALTH_ACTIVITY_METRICS: set[str] = {
    "step_count",
    "distance",
    "exercise_time",
    "workout",
}

HEALTH_WELLBEING_METRICS: set[str] = {
    "sleep",
    "mindful_session",
    "state_of_mind",
    "heart_rate",
    "resting_heart_rate",
    "hrv",
    "respiratory_rate",
    "blood_oxygen",
}

ALLOWED_STATUS_VALUES: set[str] = {
    "unread",
    "cancelled",
    "completed",
    "pending",
}

ALLOWED_PRIORITY_VALUES: set[str] = {
    "high",
    "medium",
    "low",
}

ALLOWED_SOURCE_ACCOUNT_VALUES: set[str] = {
    "gmail",
    "outlook",
    "icloud",
}

ALLOWED_HEALTH_METRICS: set[str] = HEALTH_ACTIVITY_METRICS.union(HEALTH_WELLBEING_METRICS)
ALLOWED_HEALTH_SUBDOMAINS: set[str] = {"activity", "wellbeing"}
ALLOWED_HEALTH_WORKOUT_TYPES: set[str] = {"running", "cycling", "strength"}
ALLOWED_HEALTH_AGGREGATIONS: set[str] = {"sum", "average", "count", "duration"}


def _looks_like_health_query(query: str) -> bool:
    q = (query or "").lower()
    return any(keyword in q for keyword in HEALTH_DOMAIN_KEYWORDS)


def _accept_classifier_domain(query: str, domain: Domain) -> bool:
    # Guardrail: avoid accepting speculative health classifications unless
    # the query explicitly contains health-related language.
    if domain == "health":
        return _looks_like_health_query(query)
    return True


def _resolve_health_metric(query: str) -> str:
    q = (query or "").lower()

    metric_map: list[tuple[str, list[str]]] = [
        ("resting_heart_rate", ["vilopuls", "resting heart rate"]),
        ("hrv", ["hrv", "hjärtfrekvensvariabilitet", "heart rate variability"]),
        ("heart_rate", ["hjärtfrekvens", "hjartfrekvens", "heart rate", "puls"]),
        ("respiratory_rate", ["andningsfrekvens", "andning", "respiratory rate"]),
        ("blood_oxygen", ["blodsyre", "syrenivå", "syreniva", "blood oxygen", "oxygen saturation"]),
        ("sleep", ["sömn", "somn", "sovit", "sleep"]),
        ("mindful_session", ["mindful session", "mindfulness", "mindful"]),
        ("state_of_mind", ["sinnestillstånd", "sinnestillstand", "state of mind", "mående", "maende"]),
        ("exercise_time", ["träningstid", "traningstid", "exercise time", "hur länge tränade", "hur lange tranade"]),
        ("distance", ["distans", "distance", "gått", "gatt", "walked", "walk"]),
        (
            "workout",
            [
                "träning",
                "traning",
                "tränat",
                "tranat",
                "tränade",
                "tranade",
                "workout",
                "exercise",
                "löpning",
                "lopning",
                "running",
                "cykling",
                "cycling",
                "styrka",
                "strength",
            ],
        ),
        ("step_count", ["steg", "step count", "steps"]),
    ]

    for metric, keywords in metric_map:
        if any(keyword in q for keyword in keywords):
            return metric

    return "step_count"


def _resolve_health_subdomain(query: str, metric: str) -> str:
    if metric in HEALTH_ACTIVITY_METRICS:
        return "activity"
    if metric in HEALTH_WELLBEING_METRICS:
        return "wellbeing"

    q = (query or "").lower()
    activity_words = ["steg", "step", "distans", "distance", "träning", "traning", "workout", "exercise"]
    wellbeing_words = ["sömn", "somn", "sleep", "puls", "hrv", "blodsyre", "andning", "mindful", "mående", "maende"]

    if any(word in q for word in activity_words):
        return "activity"
    if any(word in q for word in wellbeing_words):
        return "wellbeing"

    return "activity"


def _resolve_health_workout_type(query: str, metric: str) -> Optional[str]:
    if metric != "workout":
        return None

    q = (query or "").lower()
    if any(word in q for word in ("running", "run", "löpning", "lopning", "jogg", "jogging")):
        return "running"
    if any(word in q for word in ("cycling", "cycle", "cykling", "cykel")):
        return "cycling"
    if any(word in q for word in ("strength", "styrka", "gym", "weight", "weights")):
        return "strength"
    return None


def _infer_health_aggregation(metric: str) -> str:
    if metric in {"step_count", "distance", "exercise_time"}:
        return "sum"
    if metric in {"heart_rate", "resting_heart_rate", "hrv", "respiratory_rate", "blood_oxygen"}:
        return "average"
    if metric == "workout":
        return "count"
    if metric == "sleep":
        return "duration"
    return "count"


def _resolve_health_filters(query: str) -> Dict[str, object]:
    metric = _resolve_health_metric(query)
    return {
        "subdomain": _resolve_health_subdomain(query, metric),
        "metric": metric,
        "workout_type": _resolve_health_workout_type(query, metric),
        "aggregation": _infer_health_aggregation(metric),
    }


def _map_relative_n_value(n: int) -> str:
    if n == 7:
        return "7d"
    if n == 30:
        return "30d"
    if n == 90:
        return "3m"
    if n == 365:
        return "1y"
    return f"{n}d"


def _time_scope_from_time_intent(
    time_intent: TimeIntent, timeframe: Optional[Dict[str, object]]
) -> TimeScopeDTO:
    category = time_intent.category
    payload = time_intent.payload or {}
    start = timeframe.get("start") if timeframe else None
    end = timeframe.get("end") if timeframe else None

    scope_type: TimeScopeType = "all"
    scope_value: Optional[str] = None

    if category == "REL_TODAY":
        scope_type = "relative"
        scope_value = "today"
    elif category == "REL_TODAY_MORNING":
        scope_type = "relative"
        scope_value = "today_morning"
    elif category == "REL_TODAY_DAY":
        scope_type = "relative"
        scope_value = "today_day"
    elif category == "REL_TODAY_AFTERNOON":
        scope_type = "relative"
        scope_value = "today_afternoon"
    elif category == "REL_TODAY_EVENING":
        scope_type = "relative"
        scope_value = "today_evening"
    elif category == "REL_TOMORROW_MORNING":
        scope_type = "relative"
        scope_value = "tomorrow_morning"
    elif category == "REL_THIS_WEEK":
        scope_type = "relative"
        scope_value = "this_week"
    elif category == "REL_NEXT_WEEK":
        scope_type = "relative"
        scope_value = "next_week"
    elif category == "REL_LAST_WEEK":
        scope_type = "relative"
        scope_value = "last_week"
    elif category == "REL_THIS_MONTH":
        scope_type = "relative"
        scope_value = "this_month"
    elif category == "REL_NEXT_MONTH":
        scope_type = "relative"
        scope_value = "next_month"
    elif category == "REL_LAST_N_UNITS":
        n = int(payload.get("n", 0))  # pyright: ignore[reportArgumentType]
        scope_type = "relative"
        scope_value = _map_relative_n_value(n)
    elif category == "ABS_DATE_SINGLE":
        scope_type = "absolute"
        scope_value = str(payload.get("date")) if payload else "unknown"
    elif category == "REL_TOMORROW":
        scope_type = "relative"
        scope_value = "tomorrow"
    elif category == "REL_YESTERDAY":
        scope_type = "relative"
        scope_value = "yesterday"
    elif category == "NONE":
        scope_type = "all"

    return TimeScopeDTO(
        type=scope_type,
        value=scope_value,
        start=start,
        end=end,
    )


def _operation_for_query(
    domain: Domain, query: str, filters: Optional[Dict[str, object]] = None
) -> Operation:
    q = (query or "").lower().strip()

    if domain == "health":
        if (
            q.startswith("finns det")
            or q.startswith("finns det någon")
            or q.startswith("har jag några")
            or q.startswith("har jag någon")
        ):
            return "exists"
        if q.startswith("när") and any(
            k in q for k in ("senaste", "senast", "latest", "last")
        ):
            return "latest"

        aggregation = str((filters or {}).get("aggregation") or "").lower()
        if aggregation == "count":
            return "count"
        if aggregation in {"sum", "average", "duration"}:
            return "sum"
        return "count"

    # ---- Exists ----
    if (
        q.startswith("finns det")
        or q.startswith("finns det någon")
        or q.startswith("har jag några")
        or q.startswith("har jag någon")
    ):
        return "exists"

    # ---- Count ----
    if q.startswith("hur många") or "antal" in q:
        return "count"

    # ---- Sum ----
    if q.startswith("hur länge") or "hur lång tid" in q:
        return "sum"

    # ---- Latest ----
    # Only treat as 'latest' when the question is explicitly asking *when* (starts with "när")
    # e.g. "När är nästa...", "När tog jag den senaste..."
    if q.startswith("när") and any(
        k in q for k in ("nästa", "när är nästa", "senaste", "senast", "next", "last")
    ):
        return "latest"

    # ---- Explicit list phrasing ----
    if (
        q.startswith("vilka")
        or q.startswith("vad har jag")
        or q.startswith("vad är")
        or q.startswith("vad händer")
        or q.startswith("var")
    ):
        return "list"

    # ---- Search-like phrasing ----
    if any(word in q for word in ["sök", "söker", "search", "find", "hitta", "visa"]):
        return "list"

    # Safe fallback
    return "count"


def _fallback_domain_for_query(query: str) -> Domain:
    lower_q = (query or "").lower()

    if _looks_like_health_query(lower_q):
        return "health"
    if any(word in lower_q for word in ("mejl", "mail", "inkorg", "epost", "e-post")):
        return "mail"
    if any(word in lower_q for word in ("anteckning", "anteckningar", "notes", "notering")):
        return "notes"
    if any(word in lower_q for word in ("påminn", "påminnelse", "uppgift", "todo", "att göra")):
        return "reminders"
    if any(word in lower_q for word in ("kontakt", "kontakter", "telefonnummer", "adressbok")):
        return "contacts"
    if any(word in lower_q for word in ("bild", "bilder", "foto", "foton", "album", "video")):
        return "photos"
    if any(word in lower_q for word in ("fil", "filer", "dokument", "pdf", "mapp")):
        return "files"
    if any(word in lower_q for word in ("plats", "position", "var är jag", "var var jag", "besökt", "resa")):
        return "location"
    if any(word in lower_q for word in ("minne", "minnen", "memory", "historik", "mönster", "kom ihåg")):
        return "memory"

    # Deterministic default instead of clarification/analysis payload.
    return "calendar"


def _keyword_domain_for_query(query: str) -> Optional[Domain]:
    lower_q = (query or "").lower()
    explicit_map = {
        "health": list(HEALTH_DOMAIN_KEYWORDS),
        "calendar": ["kalender", "möte", "möten", "händelse", "bokning", "agenda"],
        "mail": ["mejl", "mail", "inkorg", "epost", "e-post"],
        "reminders": ["påminn", "påminnelse", "uppgift", "uppgifter", "todo", "att göra"],
        "notes": ["anteckning", "anteckningar", "notes", "notering"],
        "memory": ["minne", "minnen", "memory", "historik", "mönster", "kom ihåg", "remember"],
        "files": ["fil", "filer", "dokument", "pdf", "mapp"],
        "photos": ["bild", "bilder", "foto", "foton", "album", "video", "videor"],
        "contacts": ["kontakt", "kontakter", "telefonnummer", "adressbok"],
        "location": ["plats", "position", "var är jag", "var var jag", "besökt", "resa"],
    }
    for domain, keywords in explicit_map.items():
        if any(k in lower_q for k in keywords):
            return cast(Domain, domain)
    return None


def _is_ambiguous_fallback_query(query: str) -> bool:
    normalized = re.sub(r"[^\w\såäö]", "", (query or "").lower()).strip()
    return normalized in {
        "vad händer",
        "vad är på gång",
        "vad ar pa gang",
        "hur ser det ut",
        "är det något idag",
        "ar det nagot idag",
        "är det lugnt",
        "ar det lugnt",
    }


def _default_filters() -> Dict[str, object]:
    return {
        "status": None,
        "participants": [],
        "location": None,
        "text_contains": None,
        "tags": [],
        "priority": None,
        "has_attachment": None,
        "source_account": None,
    }


def _normalize_filter_value(value: str) -> str:
    cleaned = value.strip().strip("\"'`")
    cleaned = re.sub(r"[\s\.,;:!?]+$", "", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned.lower()


def _dedupe_terms(values: list[str]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for value in values:
        normalized = _normalize_filter_value(value)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        output.append(normalized)
    return output


def _coerce_choice(value: object, *, allowed: set[str]) -> Optional[str]:
    if not isinstance(value, str):
        return None
    normalized = _normalize_filter_value(value)
    if normalized in allowed:
        return normalized
    return None


def _coerce_optional_text(value: object) -> Optional[str]:
    if not isinstance(value, str):
        return None
    normalized = _normalize_filter_value(value)
    if not normalized:
        return None
    return normalized


def _coerce_string_list(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    values = [v for v in value if isinstance(v, str)]
    return _dedupe_terms(values)


def _coerce_optional_bool(value: object) -> Optional[bool]:
    if isinstance(value, bool):
        return value
    return None


def _extract_status(query: str, domain: Domain) -> Optional[str]:
    q = (query or "").lower()
    if domain == "mail" and re.search(r"\b(oläst|olästa|unread)\b", q):
        return "unread"
    if re.search(r"\b(inställd|cancelled|canceled|avbokad)\b", q):
        return "cancelled"
    if re.search(r"\b(klar|klart|färdig|done|completed|slutförd|avklarad)\b", q):
        return "completed"
    if re.search(r"\b(pending|öppen|open|todo|ogjord|ofärdig)\b", q) or "att göra" in q:
        return "pending"
    return None


def _extract_participants(query: str) -> list[str]:
    candidates: list[str] = []
    patterns = [
        re.compile(r"\b(?:från|from|med|till)\s+([a-z0-9åäö@._-]+(?:\s+[a-z0-9åäö@._-]+){0,2})", re.IGNORECASE),
        re.compile(r"\bfyller\s+([a-zåäö][\wåäö-]*)", re.IGNORECASE),
        re.compile(
            r"\b(?:födelsedag|fodelsedag|birthday)\s+(?:för|for)?\s*([a-zåäö][\wåäö-]*)",
            re.IGNORECASE,
        ),
    ]
    for pattern in patterns:
        candidates.extend(match.group(1) for match in pattern.finditer(query))

    disallowed = {
        "mig",
        "jag",
        "oss",
        "vi",
        "dig",
        "du",
        "idag",
        "imorgon",
        "igår",
        "vecka",
        "månad",
        "år",
        "mail",
        "mejl",
        "kalender",
    }
    cleaned = [c for c in _dedupe_terms(candidates) if c not in disallowed]
    return cleaned


def _extract_location(query: str) -> Optional[str]:
    pattern = re.compile(
        r"\b(?:i|på|at|in)\s+([a-zåäö][\wåäö-]*(?:\s+[a-zåäö][\wåäö-]*){0,2})",
        re.IGNORECASE,
    )
    for match in pattern.finditer(query):
        candidate = _normalize_filter_value(match.group(1))
        if candidate in {
            "dag",
            "vecka",
            "månad",
            "år",
            "morse",
            "eftermiddag",
            "kväll",
            "helgen",
            "inkorg",
        }:
            continue
        return candidate
    return None


def _extract_text_contains(query: str) -> Optional[str]:
    patterns = [
        re.compile(r"\b(?:om|about|innehåller|innehaller|contains?|med ämne|med amne|subject)\s+\"([^\"]+)\"", re.IGNORECASE),
        re.compile(r"\b(?:om|about|innehåller|innehaller|contains?|med ämne|med amne|subject)\s+([a-z0-9åäö][\wåäö\s@._-]{2,60})$", re.IGNORECASE),
        re.compile(r"\b(?:sök|sok|search|hitta|find)\s+(?:efter\s+)?([a-z0-9åäö][\wåäö\s@._-]{2,60})$", re.IGNORECASE),
    ]

    for pattern in patterns:
        match = pattern.search(query)
        if not match:
            continue
        value = _normalize_filter_value(match.group(1))
        if value:
            return value
    return None


def _extract_tags(query: str) -> list[str]:
    tags = re.findall(r"#([a-zA-Z0-9åäöÅÄÖ_-]{2,32})", query)
    return _dedupe_terms(tags)


def _extract_priority(query: str) -> Optional[str]:
    q = (query or "").lower()
    if any(word in q for word in ("hög prioritet", "hog prioritet", "prio hög", "prio hog", "urgent", "high priority")):
        return "high"
    if any(word in q for word in ("medel prioritet", "medium priority", "prio medel")):
        return "medium"
    if any(word in q for word in ("låg prioritet", "lag prioritet", "low priority", "prio låg", "prio lag")):
        return "low"
    return None


def _extract_has_attachment(query: str) -> Optional[bool]:
    q = (query or "").lower()
    if any(phrase in q for phrase in ("utan bilaga", "without attachment", "utan bilagor")):
        return False
    if any(phrase in q for phrase in ("med bilaga", "med bilagor", "has attachment", "with attachment")):
        return True
    return None


def _extract_source_account(query: str) -> Optional[str]:
    q = (query or "").lower()
    if any(word in q for word in ("gmail", "google mail")):
        return "gmail"
    if any(word in q for word in ("outlook", "hotmail", "live.com")):
        return "outlook"
    if any(word in q for word in ("icloud", "apple mail")):
        return "icloud"
    return None


def _resolve_non_health_filters(query: str, domain: Domain) -> Dict[str, object]:
    filters = _default_filters()

    status = _extract_status(query, domain)
    if status is not None:
        filters["status"] = status

    participants = _extract_participants(query)
    if participants:
        filters["participants"] = participants

    location = _extract_location(query)
    if location and domain in {"calendar", "reminders", "location"}:
        filters["location"] = location

    text_contains = _extract_text_contains(query)
    if text_contains:
        filters["text_contains"] = text_contains

    tags = _extract_tags(query)
    if tags:
        filters["tags"] = tags

    priority = _extract_priority(query)
    if priority and domain in {"reminders", "mail"}:
        filters["priority"] = priority

    has_attachment = _extract_has_attachment(query)
    if has_attachment is not None and domain in {"mail", "files"}:
        filters["has_attachment"] = has_attachment

    source_account = _extract_source_account(query)
    if source_account and domain == "mail":
        filters["source_account"] = source_account

    return filters


def _sanitize_llm_filters(raw_filters: Dict[str, object], *, domain: Domain) -> Dict[str, object]:
    sanitized: Dict[str, object] = {}

    if domain == "health":
        subdomain = _coerce_choice(raw_filters.get("subdomain"), allowed=ALLOWED_HEALTH_SUBDOMAINS)
        if subdomain is not None:
            sanitized["subdomain"] = subdomain

        metric = _coerce_choice(raw_filters.get("metric"), allowed=ALLOWED_HEALTH_METRICS)
        if metric is not None:
            sanitized["metric"] = metric

        workout_type = _coerce_choice(raw_filters.get("workout_type"), allowed=ALLOWED_HEALTH_WORKOUT_TYPES)
        if workout_type is not None:
            sanitized["workout_type"] = workout_type

        aggregation = _coerce_choice(raw_filters.get("aggregation"), allowed=ALLOWED_HEALTH_AGGREGATIONS)
        if aggregation is not None:
            sanitized["aggregation"] = aggregation

        return sanitized

    status = _coerce_choice(raw_filters.get("status"), allowed=ALLOWED_STATUS_VALUES)
    if status is not None:
        sanitized["status"] = status

    participants = _coerce_string_list(raw_filters.get("participants"))
    if participants:
        sanitized["participants"] = participants

    location = _coerce_optional_text(raw_filters.get("location"))
    if location is not None and domain in {"calendar", "reminders", "location"}:
        sanitized["location"] = location

    text_contains = _coerce_optional_text(raw_filters.get("text_contains"))
    if text_contains is not None:
        sanitized["text_contains"] = text_contains

    tags = _coerce_string_list(raw_filters.get("tags"))
    if tags:
        sanitized["tags"] = tags

    priority = _coerce_choice(raw_filters.get("priority"), allowed=ALLOWED_PRIORITY_VALUES)
    if priority is not None and domain in {"reminders", "mail"}:
        sanitized["priority"] = priority

    has_attachment = _coerce_optional_bool(raw_filters.get("has_attachment"))
    if has_attachment is not None and domain in {"mail", "files"}:
        sanitized["has_attachment"] = has_attachment

    source_account = _coerce_choice(raw_filters.get("source_account"), allowed=ALLOWED_SOURCE_ACCOUNT_VALUES)
    if source_account is not None and domain == "mail":
        sanitized["source_account"] = source_account

    return sanitized


def _merge_filters(
    *,
    query: str,
    domain: Domain,
    deterministic_filters: Dict[str, object],
    llm_filters: Dict[str, object],
) -> Dict[str, object]:
    if not llm_filters:
        return deterministic_filters

    merged = dict(deterministic_filters)
    merged.update(llm_filters)

    if domain == "health":
        metric = merged.get("metric")
        metric_str = str(metric) if metric is not None else ""
        if metric_str and "subdomain" not in llm_filters:
            merged["subdomain"] = _resolve_health_subdomain(query, metric_str)
        if metric_str and "aggregation" not in llm_filters:
            merged["aggregation"] = _infer_health_aggregation(metric_str)
        if metric_str != "workout":
            merged["workout_type"] = None

    return merged


class DataIntentRouter:
    def __init__(
        self,
        *,
        timezone_name: str = "Europe/Stockholm",
        now_provider: Optional[Callable[[], datetime]] = None,
    ) -> None:
        _now = now_provider or utcnow_aware

        self.domain_classifier = get_qwen_classifier()
        self.filter_structurer = get_qwen_filter_structurer()
        self.time_resolver = QueryTimeframeResolver(
            timezone_name=timezone_name, now_provider=_now
        )
        self.time_policy = TimePolicy(
            TimePolicyConfig(timezone_name=timezone_name), now_provider=_now
        )

    def route(self, query: str, language: str = "sv") -> Dict[str, object]:
        q = (query or "").strip()
        ambiguous_fallback = _is_ambiguous_fallback_query(q)

        # Fast path for explicit source keywords: avoids an LLM roundtrip for common queries.
        explicit_domain = _keyword_domain_for_query(q)
        dom = None
        if explicit_domain is None and not ambiguous_fallback:
            try:
                dom = self.domain_classifier.classify(q)
            except Exception:
                dom = None

        parsed = self.time_resolver.resolve(q)

        # Always definitively resolve domain, default to calendar
        resolved_domain: Domain = _fallback_domain_for_query(q)
        if explicit_domain is not None:
            resolved_domain = explicit_domain
        elif not ambiguous_fallback and dom is not None:
            if dom.domain is not None and _accept_classifier_domain(q, dom.domain):
                resolved_domain = dom.domain
            elif dom.suggestions:
                for suggestion in dom.suggestions:
                    if _accept_classifier_domain(q, suggestion):
                        resolved_domain = suggestion
                        break

        if resolved_domain == "health":
            deterministic_filters = _resolve_health_filters(q)
        else:
            deterministic_filters = _resolve_non_health_filters(q, resolved_domain)

        raw_llm_filters: Dict[str, object] = {}
        try:
            candidate_llm_filters = self.filter_structurer.structure_filters(
                query=q,
                domain=resolved_domain,
                language=language,
            )
            if isinstance(candidate_llm_filters, dict):
                raw_llm_filters = cast(Dict[str, object], candidate_llm_filters)
        except Exception:
            raw_llm_filters = {}

        llm_filters = _sanitize_llm_filters(raw_llm_filters, domain=resolved_domain)
        filters = _merge_filters(
            query=q,
            domain=resolved_domain,
            deterministic_filters=deterministic_filters,
            llm_filters=llm_filters,
        )

        timeframe = self.time_policy.apply(resolved_domain, parsed)
        time_scope = _time_scope_from_time_intent(parsed.time_intent, timeframe)
        operation = _operation_for_query(resolved_domain, q, filters)

        plan_payload: Dict[str, Any] = {
            "domain": resolved_domain,
            "mode": "info",
            "operation": operation,
            "time_scope": time_scope,
            "filters": filters,
        }
        plan = IntentPlanDTO.model_validate(plan_payload)
        return plan.model_dump(mode="python")
