"""
Deterministisk router som mappar användarfrågor till IntentPlanDTO-liknande DataIntent payload.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import re
from typing import Any, Callable, Dict, Optional, cast, get_args

from helpershelp.query.intent_plan import (
    Domain,
    IntentPlanDTO,
    Operation,
    TimeScopeDTO,
    TimeScopeType,
)
from helpershelp.llm import get_qwen_intent_structurer
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
ALLOWED_DOMAIN_VALUES: set[str] = set(get_args(Domain))
ALLOWED_OPERATION_VALUES: set[str] = set(get_args(Operation))

CALENDAR_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("kalender", r"\bkalender(?:n)?\b"),
    ("möte", r"\bmöte(?:n)?\b"),
    ("event", r"\bevent\b"),
    ("händelse", r"\bhändelse(?:r)?\b"),
    ("agenda", r"\bagenda\b"),
    ("bokning", r"\bbokning(?:ar)?\b"),
    ("appointment", r"\bappointment\b"),
)

CALENDAR_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("på gång", r"\bpå gång\b|\bpa gang\b"),
    ("händer", r"\bhänder\b|\bhanda\b|\bhänder det\b|\bvad händer\b"),
    ("schema", r"\bschema(?:t)?\b"),
)

MAIL_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("mejl", r"\bmejl\b|\bmail\b"),
    ("inkorg", r"\binkorg(?:en)?\b|\binbox\b"),
    ("epost", r"\bepost\b|\be-post\b|\bemail\b"),
    ("oläst", r"\boläst(?:a)?\b|\bunread\b"),
    ("bilaga", r"\bbilag(?:a|or)\b|\battachment(?:s)?\b"),
    ("ämne", r"\bämne\b|\bamne\b|\bsubject\b"),
    ("gmail", r"\bgmail\b"),
    ("outlook", r"\boutlook\b"),
)

MAIL_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("från", r"\bfrån\b|\bfrom\b"),
    ("skickat", r"\bskickat\b|\bsent\b"),
    ("avsändare", r"\bavsändare\b|\bsender\b"),
)

REMINDER_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("påminnelse", r"\bpåminn(?:else|elser)?\b"),
    ("uppgift", r"\buppgift(?:er)?\b"),
    ("att göra", r"\batt göra\b|\batt gora\b|\batt-göra\b|\batt-gora\b"),
    ("todo", r"\btodo\b|\bto do\b"),
    ("checklista", r"\bchecklista\b"),
    ("deadline", r"\bdeadline(?:s)?\b"),
)

REMINDER_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("måste göra", r"\bmåste jag göra\b|\bmaste jag gora\b|\bmåste göra\b|\bmaste gora\b"),
    ("behöver göra", r"\bbehöver jag göra\b|\bbehover jag gora\b|\bbehöver göra\b|\bbehover gora\b"),
    ("ska göra", r"\bvad ska jag göra\b|\bvad ska jag gora\b|\bska jag göra\b|\bska jag gora\b"),
    ("öppna", r"\böppna\b|\boppna\b|\bopen\b"),
    ("ogjorda", r"\bogjord(?:a)?\b|\buncompleted\b"),
    ("bocka av", r"\bbocka av\b|\bchecka av\b|\bcheck off\b"),
)

CONTACTS_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("kontakter", r"\bkontakt(?:er|en)?\b"),
    ("kontaktuppgifter", r"\bkontaktuppgift(?:er)?\b"),
    ("telefonnummer", r"\btelefonnummer(?:t)?\b"),
    ("mobilnummer", r"\bmobilnummer(?:t)?\b"),
    ("mejladress", r"\bmejladress(?:en)?\b|\bmailadress(?:en)?\b"),
    ("epostadress", r"\be-?postadress(?:en)?\b"),
    ("adressbok", r"\badressbok(?:en)?\b"),
    ("födelsedag", r"\bfödelsedag\b|\bfodelsedag\b|\bbirthday\b"),
)

CONTACTS_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("nummer till", r"\b(?:nummer|telefonnummer|mobilnummer)\s+(?:till|för|for)\b"),
    ("adress till", r"\b(?:mejladress|mailadress|e-?postadress|kontaktuppgifter)\s+(?:till|för|for)\b"),
    ("hur når jag", r"\bhur når jag\b|\bhur nar jag\b"),
    ("hur kontaktar jag", r"\bhur kontaktar jag\b"),
    ("kan jag ringa", r"\bkan jag ringa\b|\bhur ringer jag\b"),
)

FILES_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("fil", r"\bfil(?:er|en)?\b"),
    ("dokument", r"\bdokument(?:et|en)?\b"),
    ("pdf", r"\bpdf(?:en)?\b"),
    ("mapp", r"\bmapp(?:en|ar)?\b"),
    ("nedladdning", r"\bnedladd(?:ning|ningar)\b"),
)

FILES_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("importerat", r"\bimporter(?:a|at|ade)\b"),
    ("öppnat", r"\böppnat\b|\boppnat\b"),
    ("sparat", r"\bsparat\b|\bspara(?:de)?\b"),
    ("laddat ner", r"\bladdat ner\b|\bdownload(?:ed)?\b"),
    ("filnamn", r"\bfilnamn\b"),
)

PHOTOS_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("bild", r"\bbild(?:er|en)?\b"),
    ("foto", r"\bfoto(?:n)?\b"),
    ("album", r"\balbum(?:et)?\b"),
    ("video", r"\bvideo(?:r|n)?\b"),
    ("skärmdump", r"\bskärmdump(?:ar)?\b|\bskarmdump(?:ar)?\b|\bscreenshot(?:s)?\b"),
    ("kamerarulle", r"\bkamerarulle(?:n)?\b|\bcamera roll\b"),
    ("favorit", r"\bfavorit(?:er)?\b"),
)

PHOTOS_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("tagit", r"\btagit\b|\btog jag\b|\bfotat\b|\bfilm(?:at|ade)\b|\bspelat in\b"),
    ("kamera", r"\bkamera(?:n)?\b"),
    ("importerat", r"\bimporter(?:a|at|ade)\b"),
)

ASSET_ARTIFACT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("boardingkort", r"\bboardingkort(?:et)?\b"),
    ("kvitto", r"\bkvitto(?:t|n)?\b"),
    ("biljett", r"\bbiljett(?:en|er)?\b"),
    ("faktura", r"\bfaktura(?:n|r)?\b"),
    ("intyg", r"\bintyg(?:et)?\b"),
    ("kontrakt", r"\bkontrakt(?:et)?\b"),
    ("pass", r"\bpass(?:et)?\b"),
)

LOCATION_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("var är jag", r"\bvar är jag\b|\bvar ar jag\b|\bwhere am i\b"),
    ("var var jag", r"\bvar var jag\b|\bwhere was i\b"),
    ("var har jag varit", r"\bvar har jag varit\b"),
    ("plats", r"\bplats(?:en)?\b|\bposition(?:en)?\b|\blocation\b|\bgps\b"),
    ("befinner jag mig", r"\bbefinner jag mig\b|\bbefann jag mig\b"),
    ("varit på", r"\bhar jag varit\s+(?:på|pa|i)\b|\bvarit\s+(?:på|pa|i)\b"),
    ("besökt", r"\bhar jag besökt\b|\bbesökt\b|\bbesokte\b"),
    ("rest till", r"\b(?:rest|reste)\s+till\b|\b(?:åkte|akte)\s+till\b"),
)

LOCATION_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("nära", r"\bnära\b|\bnara\b|\bnear\b"),
    ("platshistorik", r"\bplatshistorik\b|\blocation history\b"),
)

NOTES_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("anteckning", r"\banteckning(?:ar|en)?\b"),
    ("notes", r"\bnotes?\b"),
    ("notering", r"\bnotering(?:ar|en)?\b"),
)

NOTES_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("sök i", r"\bsök i\b|\bsok i\b"),
    ("skrivit om", r"\b(?:skrev|skrivit|antecknat|antecknade|noterat|noterade)\b.*\bom\b"),
    ("öppnat", r"\böppnat\b|\boppnat\b"),
    ("ändrade", r"\bändrad(?:e)?\b|\bredigerad(?:e)?\b"),
    ("titel", r"\butan titel\b|\btitel\b"),
)

MEMORY_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("minne", r"\bminne(?:n)?\b"),
    ("memory", r"\bmemory\b"),
    ("historik", r"\bhistorik\b"),
    ("mönster", r"\bmönster\b|\bmonster\b"),
    ("kom ihåg", r"\bkom ihåg\b|\bkom ihag\b|\bremember\b"),
    ("sammanfattning", r"\bsammanfatt(?:ning|a)\b|\bsummera\b|\brecap\b"),
)

MEMORY_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("vad gjorde jag", r"\bvad gjorde jag\b|\bvad har jag gjort\b"),
    ("vad minns jag", r"\bvad minns jag\b"),
    ("brukar jag", r"\bvad brukar jag\b|\bbrukar jag\b"),
    ("återkommande", r"\båterkommande\b|\baterkommande\b"),
    ("nyligen", r"\bnyligen\b"),
    ("relaterat till", r"\brelaterat till\b|\bkopplat till\b"),
)

HEALTH_PRIMARY_SIGNALS: tuple[tuple[str, str], ...] = (
    ("steg", r"\bsteg\b|\bsteps?\b"),
    ("träning", r"\bträning(?:en)?\b|\btraning(?:en)?\b|\bworkout\b|\bexercise\b"),
    ("tränade", r"\bträn(?:ade|ar|at)\b|\btran(?:ade|ar|at)\b"),
    ("löpning", r"\blöpning(?:en)?\b|\blopning(?:en)?\b|\brunning\b|\bsprang\b|\bjogg(?:ade|ing)?\b"),
    ("cykling", r"\bcykl(?:ing|ade|ar)\b|\bcycling\b"),
    ("styrka", r"\bstyrka\b|\bstyrkepass\b|\bstrength\b|\bgympass\b"),
    ("sömn", r"\bsömn\b|\bsomn\b|\bsovit\b|\bsleep\b"),
    ("puls", r"\bpuls\b|\bhjärtfrekvens\b|\bhjartfrekvens\b|\bheart rate\b"),
    ("hrv", r"\bhrv\b"),
    ("blodsyre", r"\bblodsyre\b|\bblood oxygen\b"),
    ("andning", r"\bandning\b|\bandningsfrekvens\b|\brespiratory\b"),
    ("mående", r"\bmående\b|\bmaende\b|\bsinnestillstånd\b|\bsinnestillstand\b|\bstate of mind\b"),
    ("kalorier", r"\bkalori(?:er)?\b|\bcalor(?:ie|ies)\b"),
)

HEALTH_CONTEXT_SIGNALS: tuple[tuple[str, str], ...] = (
    ("hur sov jag", r"\bhur sov jag\b"),
    ("hur mådde jag", r"\bhur mådde jag\b|\bhur madde jag\b|\bhur mår jag\b|\bhur mar jag\b"),
    ("tränade jag", r"\btränade jag\b|\btranade jag\b"),
)

GENERIC_CHECKIN_PATTERNS: tuple[str, ...] = (
    r"\bvad händer\b",
    r"\bhur ser det ut\b",
    r"\bär det något\b|\bar det nagot\b",
    r"\bvad har jag\b",
    r"\bfinns det något\b|\bfinns det nagot\b",
    r"\bvad är på gång\b|\bvad ar pa gang\b",
)

TASK_CHECKIN_PATTERNS: tuple[str, ...] = (
    r"\bvad behöver jag göra\b|\bvad behover jag gora\b",
    r"\bvad måste jag göra\b|\bvad maste jag gora\b",
    r"\bvad ska jag göra\b|\bvad ska jag gora\b",
    r"\bhar jag något att göra\b|\bhar jag nagot att gora\b",
    r"\bhar jag några uppgifter\b|\bhar jag nagra uppgifter\b",
    r"\bvad har jag kvar\b",
    r"\bvad återstår\b|\bvad aterstar\b",
)

ASSET_LOOKUP_PATTERNS: tuple[str, ...] = (
    r"\bhar jag sparat\b",
    r"\bfinns det (?:en|ett|något|nagot|några|nagra)\b",
    r"\bkan du hitta\b",
    r"\bhitta\b",
    r"\bletar efter\b",
    r"\bvisa\b",
)

NOTES_SEARCH_PATTERNS: tuple[str, ...] = (
    r"\bvad (?:skrev|har jag skrivit)\b.*\bom\b",
    r"\bhar jag antecknat\b",
    r"\bantecknade jag\b",
    r"\bnoterade jag\b",
    r"\bsök i\b|\bsok i\b",
)

MEMORY_REFLECTION_PATTERNS: tuple[str, ...] = (
    r"\bvad gjorde jag\b",
    r"\bvad har jag gjort\b",
    r"\bvad minns jag\b",
    r"\bvad brukar jag\b",
    r"\bvilka mönster\b|\bvilka monster\b",
    r"\bsammanfatta\b|\bsammanfattning\b|\bsummera\b",
    r"\bhar jag gjort något\b|\bhar jag gjort nagot\b",
)

KNOWLEDGE_LOOKUP_PATTERNS: tuple[str, ...] = (
    r"\bhar jag något om\b|\bhar jag nagot om\b",
    r"\bfinns det något om\b|\bfinns det nagot om\b",
    r"\bvad har jag om\b",
    r"\bkan du hitta något om\b|\bkan du hitta nagot om\b",
)


@dataclass(frozen=True)
class DomainUnderstanding:
    resolved_domain: Optional[Domain]
    candidate_domains: list[Domain]
    confidence: str
    matched_signals: dict[str, list[str]]


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

    if domain == "location":
        if q.startswith("har jag varit") or q.startswith("har jag besökt"):
            return "exists"
        if q.startswith("när") and any(
            k in q for k in ("senaste", "senast", "latest", "last")
        ):
            return "latest"
        if _looks_like_location_question(q) or any(
            keyword in q
            for keyword in (
                "plats",
                "position",
                "besökt",
                "gps",
            )
        ):
            return "list"

    if domain == "reminders" and (
        _looks_like_task_checkin_query(q)
        or any(
            keyword in q
            for keyword in (
                "påminn",
                "uppgift",
                "todo",
                "to do",
                "att göra",
                "att gora",
                "checklista",
                "deadline",
            )
        )
    ):
        return "list"

    if domain == "contacts":
        if q.startswith("har jag") and any(
            keyword in q
            for keyword in (
                "nummer",
                "telefon",
                "kontaktuppgift",
                "kontaktuppgifter",
                "mailadress",
                "mejladress",
                "e-postadress",
                "epostadress",
                "@",
            )
        ):
            return "exists"
        if any(
            phrase in q
            for phrase in (
                "hur når jag",
                "hur nar jag",
                "hur kontaktar jag",
                "kontaktuppgift",
                "kontaktuppgifter",
                "telefonnummer",
                "mobilnummer",
                "mailadress",
                "mejladress",
                "e-postadress",
                "epostadress",
                "adressbok",
                "födelsedag",
                "fodelsedag",
            )
        ):
            return "list"

    if domain in {"files", "photos"} and q.startswith("har jag"):
        return "exists"

    if domain == "notes":
        if q.startswith("har jag") and any(
            phrase in q
            for phrase in (
                "antecknat",
                "anteckningar",
                "anteckning",
                "noterat",
                "notes",
                "något om",
                "nagot om",
            )
        ):
            return "exists"
        if _looks_like_notes_search_query(q) or any(
            keyword in q
            for keyword in (
                "anteckning",
                "anteckningar",
                "notes",
                "notering",
                "sök i",
                "sok i",
                "titel",
            )
        ):
            return "list"

    if domain == "memory":
        if q.startswith("har jag gjort") or (
            q.startswith("finns det")
            and any(keyword in q for keyword in ("historik", "minne", "memory"))
        ):
            return "exists"
        if _looks_like_memory_reflection_query(q) or any(
            keyword in q
            for keyword in (
                "minne",
                "minnen",
                "memory",
                "historik",
                "mönster",
                "monster",
                "sammanfatt",
                "kom ihåg",
                "kom ihag",
                "remember",
            )
        ):
            return "list"

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


def _is_explicit_operation_phrase(query: str, operation: Operation) -> bool:
    q = (query or "").lower().strip()
    if operation == "exists":
        return (
            q.startswith("finns det")
            or q.startswith("finns det någon")
            or q.startswith("har jag några")
            or q.startswith("har jag någon")
        )
    if operation == "count":
        return q.startswith("hur många") or "antal" in q
    if operation == "sum":
        return q.startswith("hur länge") or "hur lång tid" in q
    if operation == "latest":
        return q.startswith("när") and any(
            k in q for k in ("nästa", "när är nästa", "senaste", "senast", "next", "last")
        )
    if operation == "list":
        if (
            q.startswith("vilka")
            or q.startswith("vad har jag")
            or q.startswith("vad är")
            or q.startswith("vad händer")
            or q.startswith("var")
        ):
            return True
        return any(word in q for word in ["sök", "söker", "search", "find", "hitta", "visa"])
    return False


def _fallback_domain_for_query(query: str) -> Optional[Domain]:
    lower_q = (query or "").lower()

    if _looks_like_health_query(lower_q):
        return "health"
    if _collect_signal_matches(lower_q, NOTES_PRIMARY_SIGNALS):
        return "notes"
    if _collect_signal_matches(lower_q, MEMORY_PRIMARY_SIGNALS):
        return "memory"
    if _collect_signal_matches(lower_q, PHOTOS_PRIMARY_SIGNALS):
        return "photos"
    if _collect_signal_matches(lower_q, FILES_PRIMARY_SIGNALS):
        return "files"
    if _collect_signal_matches(lower_q, CONTACTS_PRIMARY_SIGNALS) or _collect_signal_matches(lower_q, CONTACTS_CONTEXT_SIGNALS):
        return "contacts"
    if _collect_signal_matches(lower_q, REMINDER_PRIMARY_SIGNALS):
        return "reminders"
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
    if any(word in lower_q for word in ("plats", "position", "var är jag", "var var jag", "besökt", "reste", "rest till")):
        return "location"
    if any(word in lower_q for word in ("minne", "minnen", "memory", "historik", "mönster", "kom ihåg")):
        return "memory"
    return None


def _keyword_domain_for_query(query: str) -> Optional[Domain]:
    lower_q = (query or "").lower()
    if _collect_signal_matches(lower_q, NOTES_PRIMARY_SIGNALS):
        return "notes"
    if _collect_signal_matches(lower_q, MEMORY_PRIMARY_SIGNALS):
        return "memory"
    if _collect_signal_matches(lower_q, PHOTOS_PRIMARY_SIGNALS):
        return "photos"
    if _collect_signal_matches(lower_q, FILES_PRIMARY_SIGNALS):
        return "files"
    if _collect_signal_matches(lower_q, CONTACTS_PRIMARY_SIGNALS) or _collect_signal_matches(lower_q, CONTACTS_CONTEXT_SIGNALS):
        return "contacts"
    if _collect_signal_matches(lower_q, REMINDER_PRIMARY_SIGNALS):
        return "reminders"
    if _collect_signal_matches(lower_q, CALENDAR_PRIMARY_SIGNALS):
        return "calendar"
    if _collect_signal_matches(lower_q, MAIL_PRIMARY_SIGNALS):
        return "mail"
    explicit_map = {
        "health": list(HEALTH_DOMAIN_KEYWORDS),
        "location": ["plats", "position", "var är jag", "var var jag", "besökt", "reste", "rest till"],
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


def _looks_like_generic_checkin_query(query: str) -> bool:
    q = (query or "").lower()
    return any(re.search(pattern, q) for pattern in GENERIC_CHECKIN_PATTERNS)


def _looks_like_task_checkin_query(query: str) -> bool:
    q = (query or "").lower()
    return any(re.search(pattern, q) for pattern in TASK_CHECKIN_PATTERNS)


def _looks_like_asset_lookup_query(query: str) -> bool:
    q = (query or "").lower()
    return any(re.search(pattern, q) for pattern in ASSET_LOOKUP_PATTERNS)


def _looks_like_notes_search_query(query: str) -> bool:
    q = (query or "").lower()
    return any(re.search(pattern, q) for pattern in NOTES_SEARCH_PATTERNS)


def _looks_like_memory_reflection_query(query: str) -> bool:
    q = (query or "").lower()
    return any(re.search(pattern, q) for pattern in MEMORY_REFLECTION_PATTERNS)


def _looks_like_knowledge_lookup_query(query: str) -> bool:
    q = (query or "").lower()
    return any(re.search(pattern, q) for pattern in KNOWLEDGE_LOOKUP_PATTERNS)


def _looks_like_location_question(query: str) -> bool:
    q = (query or "").lower()
    patterns = (
        r"^\s*var\s+(?:är|ar)\s+jag\b",
        r"^\s*var\s+var\s+jag\b",
        r"^\s*var\s+har\s+jag\s+varit\b",
        r"^\s*var\s+befinner\s+jag\s+mig\b",
        r"^\s*var\s+(?:tränade|tranade|sprang|joggade|cyklade)\s+jag\b",
        r"^\s*vart\s+(?:reste|åkte|akte|gick|sprang|cyklade)\s+jag\b",
    )
    return any(re.search(pattern, q) for pattern in patterns)


def _has_explicit_location_source(query: str) -> bool:
    q = (query or "").lower()
    return any(
        phrase in q
        for phrase in (
            "i platshistoriken",
            "i platsdatan",
            "i platsloggen",
        )
    )


def _has_explicit_health_source(query: str) -> bool:
    q = (query or "").lower()
    return any(
        phrase in q
        for phrase in (
            "i hälsodatan",
            "i hälsan",
            "in health data",
        )
    )


def _collect_signal_matches(query: str, patterns: tuple[tuple[str, str], ...]) -> list[str]:
    q = (query or "").lower()
    matches: list[str] = []
    for label, pattern in patterns:
        if re.search(pattern, q):
            matches.append(label)
    return matches


def _sorted_candidate_domains(scores: dict[Domain, int]) -> list[Domain]:
    ordered = sorted(scores.items(), key=lambda item: (-item[1], item[0]))
    return [domain for domain, score in ordered if score > 0]


def _resolve_calendar_mail_understanding(
    query: str,
    parsed_time_intent: TimeIntent,
) -> Optional[DomainUnderstanding]:
    calendar_primary = _collect_signal_matches(query, CALENDAR_PRIMARY_SIGNALS)
    calendar_context = _collect_signal_matches(query, CALENDAR_CONTEXT_SIGNALS)
    mail_primary = _collect_signal_matches(query, MAIL_PRIMARY_SIGNALS)
    mail_context = _collect_signal_matches(query, MAIL_CONTEXT_SIGNALS)

    has_time_signal = parsed_time_intent.category != "NONE"
    generic_checkin = _is_ambiguous_fallback_query(query) or _looks_like_generic_checkin_query(query)

    calendar_signals = list(calendar_primary)
    if calendar_context:
        calendar_signals.extend(calendar_context)
    if has_time_signal:
        calendar_signals.append(f"time:{parsed_time_intent.category.lower()}")

    mail_signals = list(mail_primary)
    if mail_context:
        mail_signals.extend(mail_context)

    calendar_score = len(calendar_primary) * 3 + len(calendar_context)
    mail_score = len(mail_primary) * 3 + len(mail_context)
    immediate_checkin_categories = {
        "REL_TODAY",
        "REL_TODAY_MORNING",
        "REL_TODAY_DAY",
        "REL_TODAY_AFTERNOON",
        "REL_TODAY_EVENING",
        "REL_TOMORROW",
        "REL_TOMORROW_MORNING",
    }

    if has_time_signal:
        calendar_score += 1

    if generic_checkin and not calendar_primary and not mail_primary:
        scores: dict[Domain, int] = {
            "calendar": max(calendar_score, 1),
            "mail": max(mail_score, 1),
        }
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=_sorted_candidate_domains(scores) or ["calendar", "mail"],
            confidence="low",
            matched_signals={
                "calendar": _dedupe_terms(calendar_signals),
                "mail": _dedupe_terms(mail_signals),
            },
        )

    if calendar_score <= 0 and mail_score <= 0:
        return None

    scores = {"calendar": calendar_score, "mail": mail_score}
    candidate_domains = _sorted_candidate_domains(scores)
    top_domain = candidate_domains[0] if candidate_domains else None
    second_score = scores[candidate_domains[1]] if len(candidate_domains) > 1 else 0
    top_score = scores[top_domain] if top_domain is not None else 0

    if top_domain is None:
        return None

    if len(candidate_domains) > 1 and abs(top_score - second_score) <= 1:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=candidate_domains,
            confidence="low",
            matched_signals={
                "calendar": _dedupe_terms(calendar_signals),
                "mail": _dedupe_terms(mail_signals),
            },
        )

    if (
        top_domain == "calendar"
        and has_time_signal
        and not calendar_primary
        and top_score <= 1
        and parsed_time_intent.category in immediate_checkin_categories
    ):
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=["calendar", "mail"],
            confidence="low",
            matched_signals={
                "calendar": _dedupe_terms(calendar_signals),
                "mail": _dedupe_terms(mail_signals),
            },
        )

    confidence = "high" if top_score >= 3 and top_score - second_score >= 2 else "medium"
    return DomainUnderstanding(
        resolved_domain=top_domain,
        candidate_domains=candidate_domains,
        confidence=confidence,
        matched_signals={
            "calendar": _dedupe_terms(calendar_signals),
            "mail": _dedupe_terms(mail_signals),
        },
    )


def _resolve_reminder_understanding(
    query: str,
    parsed_time_intent: TimeIntent,
) -> Optional[DomainUnderstanding]:
    reminder_primary = _collect_signal_matches(query, REMINDER_PRIMARY_SIGNALS)
    reminder_context = _collect_signal_matches(query, REMINDER_CONTEXT_SIGNALS)
    calendar_primary = _collect_signal_matches(query, CALENDAR_PRIMARY_SIGNALS)
    calendar_context = _collect_signal_matches(query, CALENDAR_CONTEXT_SIGNALS)

    has_time_signal = parsed_time_intent.category != "NONE"
    task_checkin = _looks_like_task_checkin_query(query)

    reminder_signals = list(reminder_primary)
    if reminder_context:
        reminder_signals.extend(reminder_context)
    if task_checkin:
        reminder_signals.append("task_checkin")

    calendar_signals = list(calendar_primary)
    if calendar_context:
        calendar_signals.extend(calendar_context)

    if has_time_signal:
        time_signal = f"time:{parsed_time_intent.category.lower()}"
        reminder_signals.append(time_signal)
        calendar_signals.append(time_signal)

    reminder_score = len(reminder_primary) * 3 + len(reminder_context) * 2
    if task_checkin:
        reminder_score += 2

    calendar_score = len(calendar_primary) * 3 + len(calendar_context)
    if has_time_signal:
        calendar_score += 1

    if reminder_score <= 0:
        return None

    matched_signals = {
        "reminders": _dedupe_terms(reminder_signals),
        "calendar": _dedupe_terms(calendar_signals),
    }

    if task_checkin and has_time_signal and not reminder_primary and not calendar_primary:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=["reminders", "calendar"],
            confidence="low",
            matched_signals=matched_signals,
        )

    if reminder_primary and calendar_primary:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=_sorted_candidate_domains(
                {"reminders": reminder_score, "calendar": calendar_score}
            ) or ["reminders", "calendar"],
            confidence="low",
            matched_signals=matched_signals,
        )

    if calendar_primary and reminder_score <= 2:
        return None

    scores: dict[Domain, int] = {"reminders": reminder_score, "calendar": calendar_score}
    candidate_domains = _sorted_candidate_domains(scores) or ["reminders"]
    top_domain = candidate_domains[0]
    second_score = scores[candidate_domains[1]] if len(candidate_domains) > 1 else 0
    top_score = scores[top_domain]

    if top_domain != "reminders":
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=["reminders", "calendar"],
            confidence="low",
            matched_signals=matched_signals,
        )

    if not reminder_primary and task_checkin:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=["reminders", "calendar"],
            confidence="low",
            matched_signals=matched_signals,
        )

    if len(candidate_domains) > 1 and second_score > 0 and abs(top_score - second_score) <= 1:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=candidate_domains,
            confidence="low",
            matched_signals=matched_signals,
        )

    confidence = "high" if reminder_primary and top_score >= 3 and top_score - second_score >= 2 else "medium"
    return DomainUnderstanding(
        resolved_domain="reminders",
        candidate_domains=candidate_domains,
        confidence=confidence,
        matched_signals=matched_signals,
    )


def _resolve_contacts_understanding(query: str) -> Optional[DomainUnderstanding]:
    contacts_primary = _collect_signal_matches(query, CONTACTS_PRIMARY_SIGNALS)
    contacts_context = _collect_signal_matches(query, CONTACTS_CONTEXT_SIGNALS)
    mail_primary = _collect_signal_matches(query, MAIL_PRIMARY_SIGNALS)
    mail_context = _collect_signal_matches(query, MAIL_CONTEXT_SIGNALS)

    contacts_score = len(contacts_primary) * 3 + len(contacts_context) * 2
    mail_score = len(mail_primary) * 3 + len(mail_context)

    if contacts_score <= 0:
        return None

    matched_signals = {
        "contacts": _dedupe_terms([*contacts_primary, *contacts_context]),
        "mail": _dedupe_terms([*mail_primary, *mail_context]),
    }

    scores: dict[Domain, int] = {"contacts": contacts_score, "mail": mail_score}
    candidate_domains = _sorted_candidate_domains(scores) or ["contacts"]
    top_domain = candidate_domains[0]
    second_score = scores[candidate_domains[1]] if len(candidate_domains) > 1 else 0
    top_score = scores[top_domain]

    if len(candidate_domains) > 1 and second_score > 0 and abs(top_score - second_score) <= 1:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=candidate_domains,
            confidence="low",
            matched_signals=matched_signals,
        )

    if top_domain != "contacts":
        return None

    confidence = "high" if contacts_primary and top_score >= 3 and top_score - second_score >= 2 else "medium"
    return DomainUnderstanding(
        resolved_domain="contacts",
        candidate_domains=candidate_domains,
        confidence=confidence,
        matched_signals=matched_signals,
    )


def _resolve_files_photos_understanding(
    query: str,
    parsed_time_intent: TimeIntent,
) -> Optional[DomainUnderstanding]:
    files_primary = _collect_signal_matches(query, FILES_PRIMARY_SIGNALS)
    files_context = _collect_signal_matches(query, FILES_CONTEXT_SIGNALS)
    photos_primary = _collect_signal_matches(query, PHOTOS_PRIMARY_SIGNALS)
    photos_context = _collect_signal_matches(query, PHOTOS_CONTEXT_SIGNALS)
    artifact_terms = _collect_signal_matches(query, ASSET_ARTIFACT_SIGNALS)

    has_time_signal = parsed_time_intent.category != "NONE"
    asset_lookup = _looks_like_asset_lookup_query(query) and bool(artifact_terms)

    files_signals = list(files_primary)
    if files_context:
        files_signals.extend(files_context)
    if artifact_terms:
        files_signals.extend(artifact_terms)

    photos_signals = list(photos_primary)
    if photos_context:
        photos_signals.extend(photos_context)
    if artifact_terms:
        photos_signals.extend(artifact_terms)

    if has_time_signal:
        time_signal = f"time:{parsed_time_intent.category.lower()}"
        files_signals.append(time_signal)
        photos_signals.append(time_signal)

    files_score = len(files_primary) * 3 + len(files_context) * 2
    photos_score = len(photos_primary) * 3 + len(photos_context) * 2

    if has_time_signal and (photos_primary or photos_context):
        photos_score += 1

    if asset_lookup and not files_primary and not photos_primary:
        scores: dict[Domain, int] = {
            "files": max(files_score, 1),
            "photos": max(photos_score, 1),
        }
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=_sorted_candidate_domains(scores) or ["files", "photos"],
            confidence="low",
            matched_signals={
                "files": _dedupe_terms(files_signals),
                "photos": _dedupe_terms(photos_signals),
            },
        )

    if files_score <= 0 and photos_score <= 0:
        return None

    scores = {"files": files_score, "photos": photos_score}
    candidate_domains = _sorted_candidate_domains(scores)
    top_domain = candidate_domains[0] if candidate_domains else None
    second_score = scores[candidate_domains[1]] if len(candidate_domains) > 1 else 0
    top_score = scores[top_domain] if top_domain is not None else 0

    if top_domain is None:
        return None

    if len(candidate_domains) > 1 and second_score > 0 and abs(top_score - second_score) <= 1:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=candidate_domains,
            confidence="low",
            matched_signals={
                "files": _dedupe_terms(files_signals),
                "photos": _dedupe_terms(photos_signals),
            },
        )

    confidence = "high" if top_score >= 3 and top_score - second_score >= 2 else "medium"
    return DomainUnderstanding(
        resolved_domain=top_domain,
        candidate_domains=candidate_domains,
        confidence=confidence,
        matched_signals={
            "files": _dedupe_terms(files_signals),
            "photos": _dedupe_terms(photos_signals),
        },
    )


def _resolve_notes_memory_understanding(
    query: str,
    parsed_time_intent: TimeIntent,
) -> Optional[DomainUnderstanding]:
    notes_primary = _collect_signal_matches(query, NOTES_PRIMARY_SIGNALS)
    notes_context = _collect_signal_matches(query, NOTES_CONTEXT_SIGNALS)
    memory_primary = _collect_signal_matches(query, MEMORY_PRIMARY_SIGNALS)
    memory_context = _collect_signal_matches(query, MEMORY_CONTEXT_SIGNALS)

    notes_search = _looks_like_notes_search_query(query)
    memory_reflection = _looks_like_memory_reflection_query(query)
    knowledge_lookup = _looks_like_knowledge_lookup_query(query)
    has_time_signal = parsed_time_intent.category != "NONE"

    notes_signals = list(notes_primary)
    if notes_context:
        notes_signals.extend(notes_context)
    if notes_search:
        notes_signals.append("notes_search")

    memory_signals = list(memory_primary)
    if memory_context:
        memory_signals.extend(memory_context)
    if memory_reflection:
        memory_signals.append("memory_reflection")

    if has_time_signal:
        time_signal = f"time:{parsed_time_intent.category.lower()}"
        if notes_primary or notes_context or notes_search:
            notes_signals.append(time_signal)
        if memory_primary or memory_context or memory_reflection or knowledge_lookup:
            memory_signals.append(time_signal)

    notes_score = len(notes_primary) * 3 + len(notes_context) * 2
    if notes_search:
        notes_score += 2
    if notes_primary and not memory_reflection:
        notes_score += 2

    memory_score = len(memory_primary) * 3 + len(memory_context) * 2
    if memory_reflection:
        memory_score += 2
    if has_time_signal and (memory_primary or memory_context or memory_reflection):
        memory_score += 1

    matched_signals = {
        "notes": _dedupe_terms(notes_signals),
        "memory": _dedupe_terms(memory_signals),
    }

    if knowledge_lookup and not notes_primary and not memory_primary:
        scores: dict[Domain, int] = {
            "notes": max(notes_score, 1),
            "memory": max(memory_score, 1),
        }
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=_sorted_candidate_domains(scores) or ["notes", "memory"],
            confidence="low",
            matched_signals=matched_signals,
        )

    if notes_score <= 0 and memory_score <= 0:
        return None

    scores = {"notes": notes_score, "memory": memory_score}
    candidate_domains = _sorted_candidate_domains(scores)
    top_domain = candidate_domains[0] if candidate_domains else None
    second_score = scores[candidate_domains[1]] if len(candidate_domains) > 1 else 0
    top_score = scores[top_domain] if top_domain is not None else 0

    if top_domain is None:
        return None

    if len(candidate_domains) > 1 and second_score > 0 and abs(top_score - second_score) <= 1:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=candidate_domains,
            confidence="low",
            matched_signals=matched_signals,
        )

    confidence = "medium"
    if top_domain == "notes" and (notes_primary or notes_search) and top_score >= 3 and top_score - second_score >= 2:
        confidence = "high"
    if top_domain == "memory" and (memory_primary or memory_reflection) and top_score >= 3 and top_score - second_score >= 2:
        confidence = "high"

    return DomainUnderstanding(
        resolved_domain=top_domain,
        candidate_domains=candidate_domains,
        confidence=confidence,
        matched_signals=matched_signals,
    )


def _resolve_location_health_understanding(
    query: str,
    parsed_time_intent: TimeIntent,
) -> Optional[DomainUnderstanding]:
    location_primary = _collect_signal_matches(query, LOCATION_PRIMARY_SIGNALS)
    location_context = _collect_signal_matches(query, LOCATION_CONTEXT_SIGNALS)
    health_primary = _collect_signal_matches(query, HEALTH_PRIMARY_SIGNALS)
    health_context = _collect_signal_matches(query, HEALTH_CONTEXT_SIGNALS)

    location_question = _looks_like_location_question(query)
    explicit_location_source = _has_explicit_location_source(query)
    explicit_health_source = _has_explicit_health_source(query)
    health_like = _looks_like_health_query(query)
    health_metric = _resolve_health_metric(query) if health_like else None
    extracted_location = _extract_location(query)
    has_time_signal = parsed_time_intent.category != "NONE"

    location_signals = list(location_primary)
    if location_context:
        location_signals.extend(location_context)
    if location_question:
        location_signals.append("location_question")
    if explicit_location_source:
        location_signals.append("explicit_source")
    if extracted_location and (location_primary or location_question):
        location_signals.append(extracted_location)

    health_signals = list(health_primary)
    if health_context:
        health_signals.extend(health_context)
    if explicit_health_source:
        health_signals.append("explicit_source")
    if health_metric is not None:
        health_signals.append(f"metric:{health_metric}")

    if has_time_signal:
        time_signal = f"time:{parsed_time_intent.category.lower()}"
        if location_primary or location_question:
            location_signals.append(time_signal)
        if health_like:
            health_signals.append(time_signal)

    location_score = len(location_primary) * 3 + len(location_context) * 2
    if location_question and (location_primary or health_like):
        location_score += 1
    if explicit_location_source:
        location_score += 3
    if extracted_location and (location_primary or location_question):
        location_score += 1

    health_score = len(health_primary) * 3 + len(health_context) * 2
    if health_like:
        health_score = max(health_score, 1)
    if explicit_health_source:
        health_score += 3
    if health_metric is not None:
        health_score += 1
    if has_time_signal and health_like:
        health_score += 1

    if location_score <= 0 and health_score <= 0:
        return None

    matched_signals = {
        "location": _dedupe_terms(location_signals),
        "health": _dedupe_terms(health_signals),
    }

    if explicit_location_source and not explicit_health_source:
        return DomainUnderstanding(
            resolved_domain="location",
            candidate_domains=["location", "health"],
            confidence="high",
            matched_signals=matched_signals,
        )

    if explicit_health_source and not explicit_location_source:
        return DomainUnderstanding(
            resolved_domain="health",
            candidate_domains=["health", "location"],
            confidence="high",
            matched_signals=matched_signals,
        )

    if location_question and health_score > 0:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=["location", "health"],
            confidence="low",
            matched_signals=matched_signals,
        )

    scores: dict[Domain, int] = {
        "location": location_score,
        "health": health_score,
    }
    candidate_domains = _sorted_candidate_domains(scores)
    top_domain = candidate_domains[0] if candidate_domains else None
    second_score = scores[candidate_domains[1]] if len(candidate_domains) > 1 else 0
    top_score = scores[top_domain] if top_domain is not None else 0

    if top_domain is None:
        return None

    if len(candidate_domains) > 1 and second_score > 0 and abs(top_score - second_score) <= 1:
        return DomainUnderstanding(
            resolved_domain=None,
            candidate_domains=candidate_domains,
            confidence="low",
            matched_signals=matched_signals,
        )

    confidence = "high" if top_score >= 3 and top_score - second_score >= 2 else "medium"
    return DomainUnderstanding(
        resolved_domain=top_domain,
        candidate_domains=candidate_domains,
        confidence=confidence,
        matched_signals=matched_signals,
    )


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


def _coerce_domain(value: object) -> Optional[Domain]:
    if not isinstance(value, str):
        return None
    normalized = _normalize_filter_value(value)
    if normalized in ALLOWED_DOMAIN_VALUES:
        return cast(Domain, normalized)
    return None


def _coerce_operation(value: object) -> Optional[Operation]:
    if not isinstance(value, str):
        return None
    normalized = _normalize_filter_value(value)
    if normalized in ALLOWED_OPERATION_VALUES:
        return cast(Operation, normalized)
    return None


def _extract_status(query: str, domain: Domain) -> Optional[str]:
    q = (query or "").lower()
    if domain == "mail" and re.search(r"\b(oläst|olästa|unread)\b", q):
        return "unread"
    if re.search(r"\b(inställd|cancelled|canceled|avbokad)\b", q):
        return "cancelled"
    if re.search(r"\b(klar|klart|färdig|done|completed|slutförd|avklarad)\b", q):
        return "completed"
    if re.search(r"\b(pending|öppen|öppna|oppna|open|todo|ogjord|ogjorda|ofärdig)\b", q) or "att göra" in q:
        return "pending"
    return None


def _extract_participants(query: str) -> list[str]:
    candidates: list[str] = []
    patterns = [
        re.compile(r"\b(?:från|from|till)\s+([a-z0-9åäö@._-]+(?:\s+[a-z0-9åäö@._-]+){0,2})", re.IGNORECASE),
        re.compile(r"\bmed\s+([a-z0-9åäö@._-]+(?:\s+[a-z0-9åäö@._-]+){0,2})", re.IGNORECASE),
        re.compile(r"\bfyller\s+([a-zåäö][\wåäö-]*)", re.IGNORECASE),
        re.compile(
            r"\b([a-zåäö][\wåäö-]*(?:\s+[a-zåäö][\wåäö-]*){0,1})s\s+"
            r"(?:nummer|telefonnummer|mobilnummer|mailadress|mejladress|e-?postadress|kontaktuppgifter)\b",
            re.IGNORECASE,
        ),
        re.compile(
            r"\b(?:når jag|nar jag|kontaktar jag|ringer jag)\s+"
            r"([a-z0-9åäö@._-]+(?:\s+[a-z0-9åäö@._-]+){0,2})",
            re.IGNORECASE,
        ),
        re.compile(
            r"\b(?:födelsedag|fodelsedag|birthday)\s+(?:för|for)?\s*([a-zåäö][\wåäö-]*)",
            re.IGNORECASE,
        ),
    ]
    for pattern in patterns:
        candidates.extend(match.group(1) for match in pattern.finditer(query))

    normalized_candidates: list[str] = []
    for candidate in candidates:
        normalized = _normalize_filter_value(candidate)
        if " från " in normalized:
            normalized = normalized.rsplit(" från ", 1)[-1]
        if " from " in normalized:
            normalized = normalized.rsplit(" from ", 1)[-1]
        if normalized:
            normalized_candidates.append(normalized)

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
    cleaned = [c for c in _dedupe_terms(normalized_candidates) if c not in disallowed]
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
        candidate = re.sub(
            r"\s+(?:idag|imorgon|igår|i morse|ikväll|forra veckan|förra veckan|nästa vecka|den här veckan)$",
            "",
            candidate,
        ).strip()
        if not candidate:
            continue
        return candidate
    return None


def _extract_text_contains(query: str) -> Optional[str]:
    patterns = [
        re.compile(r"\b(?:om|about|innehåller|innehaller|contains?|med ämne|med amne|subject)\s+\"([^\"]+)\"", re.IGNORECASE),
        re.compile(r"\b(?:om|about|innehåller|innehaller|contains?|med ämne|med amne|subject)\s+([a-z0-9åäö][\wåäö\s@._-]{2,60})(?:[?!.]+)?$", re.IGNORECASE),
        re.compile(r"\b(?:sök|sok|search|hitta|find)\s+(?:efter\s+)?([a-z0-9åäö][\wåäö\s@._-]{2,60})(?:[?!.]+)?$", re.IGNORECASE),
    ]

    for pattern in patterns:
        match = pattern.search(query)
        if not match:
            continue
        value = _normalize_filter_value(match.group(1))
        if value:
            return value
    return None


def _extract_asset_text_contains(query: str, domain: Domain) -> Optional[str]:
    artifacts = _collect_signal_matches(query, ASSET_ARTIFACT_SIGNALS)
    if artifacts:
        return artifacts[0]

    if domain == "photos":
        patterns = [
            re.compile(
                r"\b(?:bild|bilder|foto|foton|video|videor|skärmdump(?:ar)?|skarmdump(?:ar)?|screenshot(?:s)?)\s+"
                r"(?:på|av|med|från|fran)\s+([a-z0-9åäö][\wåäö\s@._-]{2,60})(?:[?!.]+)?$",
                re.IGNORECASE,
            )
        ]
    elif domain == "files":
        patterns = [
            re.compile(
                r"\b(?:fil|filer|dokument|pdf|mapp)\s+(?:om|med|för|for)\s+([a-z0-9åäö][\wåäö\s@._-]{2,60})(?:[?!.]+)?$",
                re.IGNORECASE,
            )
        ]
    else:
        patterns = []

    for pattern in patterns:
        match = pattern.search(query)
        if not match:
            continue
        value = _normalize_filter_value(match.group(1))
        if value:
            return value
    return None


def _extract_knowledge_text_contains(query: str) -> Optional[str]:
    patterns = [
        re.compile(
            r"\b(?:om|kring|gällande|galande|relaterat till|kopplat till)\s+([a-z0-9åäö][\wåäö\s@._-]{2,60})(?:[?!.]+)?$",
            re.IGNORECASE,
        ),
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

    if domain in {"files", "photos"}:
        text_contains = _extract_asset_text_contains(query, domain) or _extract_text_contains(query)
    elif domain in {"notes", "memory"}:
        text_contains = _extract_knowledge_text_contains(query) or _extract_text_contains(query)
    else:
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


def _llm_domain_has_explicit_signal(
    *,
    keyword_domain: Optional[Domain],
    llm_domain: Optional[Domain],
) -> bool:
    if llm_domain is None:
        return False
    return keyword_domain == llm_domain


def _resolve_special_understanding(
    *,
    query: str,
    keyword_domain: Optional[Domain],
    parsed_time_intent: TimeIntent,
) -> Optional[DomainUnderstanding]:
    resolvers: list[Optional[DomainUnderstanding]] = []

    if keyword_domain in {None, "location", "health"}:
        resolvers.append(_resolve_location_health_understanding(query, parsed_time_intent))

    if keyword_domain in {None, "reminders", "calendar"}:
        resolvers.append(_resolve_reminder_understanding(query, parsed_time_intent))

    if keyword_domain in {None, "contacts", "mail"}:
        resolvers.append(_resolve_contacts_understanding(query))

    if keyword_domain in {None, "files", "photos"}:
        resolvers.append(_resolve_files_photos_understanding(query, parsed_time_intent))

    if keyword_domain in {None, "notes", "memory"}:
        resolvers.append(_resolve_notes_memory_understanding(query, parsed_time_intent))

    if keyword_domain in {None, "calendar", "mail"}:
        resolvers.append(_resolve_calendar_mail_understanding(query, parsed_time_intent))

    for understanding in resolvers:
        if understanding is not None:
            return understanding
    return None


class DataIntentRouter:
    def __init__(
        self,
        *,
        timezone_name: str = "Europe/Stockholm",
        now_provider: Optional[Callable[[], datetime]] = None,
    ) -> None:
        _now = now_provider or utcnow_aware

        self.intent_structurer = get_qwen_intent_structurer()
        self.time_resolver = QueryTimeframeResolver(
            timezone_name=timezone_name, now_provider=_now
        )
        self.time_policy = TimePolicy(
            TimePolicyConfig(timezone_name=timezone_name), now_provider=_now
        )

    def route(self, query: str, language: str = "sv") -> Dict[str, object]:
        q = (query or "").strip()

        parsed = self.time_resolver.resolve(q)
        keyword_domain = _keyword_domain_for_query(q)
        special_understanding = _resolve_special_understanding(
            query=q,
            keyword_domain=keyword_domain,
            parsed_time_intent=parsed.time_intent,
        )

        raw_llm_intent: Dict[str, object] = {}
        try:
            candidate_llm_intent = self.intent_structurer.structure_intent(
                query=q,
                language=language,
            )
            if isinstance(candidate_llm_intent, dict):
                raw_llm_intent = cast(Dict[str, object], candidate_llm_intent)
        except Exception:
            raw_llm_intent = {}

        llm_domain = _coerce_domain(raw_llm_intent.get("domain"))
        if llm_domain is not None and not _accept_classifier_domain(q, llm_domain):
            llm_domain = None
        if llm_domain in {"calendar", "mail", "reminders", "contacts", "files", "photos", "notes", "memory", "location", "health"}:
            llm_domain = None
        elif not _llm_domain_has_explicit_signal(
            keyword_domain=keyword_domain,
            llm_domain=llm_domain,
        ):
            llm_domain = None

        clarification_filters: Dict[str, object] = {}
        if special_understanding is not None:
            clarification_filters = {
                "_confidence": special_understanding.confidence,
                "_candidate_domains": special_understanding.candidate_domains,
                "_matched_signals": special_understanding.matched_signals,
            }
            if special_understanding.resolved_domain is None:
                time_scope = _time_scope_from_time_intent(parsed.time_intent, parsed.timeframe)
                plan = IntentPlanDTO.model_validate(
                    {
                        "domain": "system",
                        "mode": "info",
                        "operation": "needs_clarification",
                        "time_scope": time_scope,
                        "filters": clarification_filters,
                    }
                )
                return plan.model_dump(mode="python")
            resolved_domain = special_understanding.resolved_domain
        else:
            resolved_domain = None

        if resolved_domain is None:
            resolved_domain = keyword_domain or llm_domain or _fallback_domain_for_query(q) or "calendar"

        if resolved_domain == "health":
            deterministic_filters = _resolve_health_filters(q)
        else:
            deterministic_filters = _resolve_non_health_filters(q, resolved_domain)

        raw_filters = raw_llm_intent.get("filters")
        raw_llm_filters = cast(Dict[str, object], raw_filters) if isinstance(raw_filters, dict) else {}

        llm_filters = _sanitize_llm_filters(raw_llm_filters, domain=resolved_domain)
        filters = _merge_filters(
            query=q,
            domain=resolved_domain,
            deterministic_filters=deterministic_filters,
            llm_filters=llm_filters,
        )
        filters.update(clarification_filters)

        timeframe = self.time_policy.apply(resolved_domain, parsed)
        time_scope = _time_scope_from_time_intent(parsed.time_intent, timeframe)
        heuristic_operation = _operation_for_query(resolved_domain, q, filters)
        llm_operation = _coerce_operation(raw_llm_intent.get("operation"))
        if llm_operation is not None and _is_explicit_operation_phrase(q, llm_operation):
            operation = llm_operation
        else:
            operation = heuristic_operation

        plan_payload: Dict[str, Any] = {
            "domain": resolved_domain,
            "mode": "info",
            "operation": operation,
            "time_scope": time_scope,
            "filters": filters,
        }
        plan = IntentPlanDTO.model_validate(plan_payload)
        return plan.model_dump(mode="python")
