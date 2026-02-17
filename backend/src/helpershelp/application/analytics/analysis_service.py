from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Sequence

from helpershelp.application.analytics.intent_parser import (
    CALENDAR_LEAST_LOADED_DAY_INTENT,
    CALENDAR_SPECIFIC_DAY_INTENT,
    IntentParser,
)
from helpershelp.application.analytics.temporal.resolver import TemporalResolver, TimeWindow
from helpershelp.domain.value_objects.time_utils import utcnow

logger = logging.getLogger(__name__)

REASON_CALENDAR_DATA_MISSING = "calendar_data_missing"
REASON_CALENDAR_DATA_STALE = "calendar_data_stale"
REASON_CALENDAR_COVERAGE_GAP = "calendar_coverage_gap"


@dataclass(frozen=True)
class AnalysisResult:
    intent_id: str
    time_window: TimeWindow
    insights: List[dict]
    patterns: List[dict]
    limitations: List[str]
    confidence: Optional[float]
    evidence_items: List[dict]


class AnalysisService:
    """Analytics-only path driven by calendar feature-store snapshots."""

    def __init__(
        self,
        *,
        intent_parser: Optional[IntentParser] = None,
        temporal_resolver: Optional[TemporalResolver] = None,
        text_service=None,
        calendar_ttl_hours: int = 24,
    ):
        self.intent_parser = intent_parser or IntentParser()
        self.temporal_resolver = temporal_resolver or TemporalResolver()
        self.text_service = text_service
        self.calendar_ttl_hours = max(1, int(calendar_ttl_hours))

    def parse_intent(self, query: str):
        return self.intent_parser.parse(query)

    def handle(self, *, query: str, language: str, store, now: Optional[datetime] = None) -> Dict:
        parsed = self.parse_intent(query)
        if not parsed:
            raise ValueError("No analytics intent matched")

        resolved_now = now or utcnow()
        time_window = self.temporal_resolver.resolve(
            query=query,
            intent_id=parsed.intent_id,
            now=resolved_now,
        )

        readiness = self._evaluate_calendar_readiness(
            store=store,
            time_window=time_window,
            now=resolved_now,
        )
        if not readiness["ready"]:
            limitations = self._limitations_for_reasons(readiness["reason_codes"])
            analysis = AnalysisResult(
                intent_id=parsed.intent_id,
                time_window=time_window,
                insights=[],
                patterns=[],
                limitations=limitations,
                confidence=None,
                evidence_items=[],
            )
            return self._build_response(
                query=query,
                language=language,
                analysis=analysis,
                analysis_ready=False,
                requires_sources=["calendar"],
                reason_codes=readiness["reason_codes"],
                required_time_window=time_window,
                use_llm=False,
            )

        events = store.list_calendar_feature_events(
            start=self._to_aware_utc(time_window.start),
            end=self._to_aware_utc(time_window.end),
            limit=10000,
        )

        if parsed.intent_id == CALENDAR_SPECIFIC_DAY_INTENT:
            analysis = self._calculate_calendar_specific_day(events=events, window=time_window)
        elif parsed.intent_id == CALENDAR_LEAST_LOADED_DAY_INTENT:
            analysis = self._calculate_calendar_least_loaded_day(events=events, window=time_window)
        else:
            analysis = AnalysisResult(
                intent_id=parsed.intent_id,
                time_window=time_window,
                insights=[],
                patterns=[],
                limitations=["Intent stöds inte i Fas 1."],
                confidence=0.0,
                evidence_items=[],
            )

        return self._build_response(
            query=query,
            language=language,
            analysis=analysis,
            analysis_ready=True,
            requires_sources=[],
            reason_codes=[],
            required_time_window=None,
            use_llm=True,
        )

    def _build_response(
        self,
        *,
        query: str,
        language: str,
        analysis: AnalysisResult,
        analysis_ready: bool,
        requires_sources: List[str],
        reason_codes: List[str],
        required_time_window: Optional[TimeWindow],
        use_llm: bool,
    ) -> Dict:
        if use_llm:
            content = self._render_narrative(query=query, language=language, analysis=analysis)
        else:
            content = self._missing_data_narrative(reason_codes=reason_codes, limitations=analysis.limitations)

        required_window_payload = None
        if required_time_window:
            required_window_payload = {
                "start": self._to_naive_utc(required_time_window.start),
                "end": self._to_naive_utc(required_time_window.end),
                "granularity": required_time_window.granularity,
            }

        return {
            "content": content,
            "evidence_items": analysis.evidence_items,
            "used_sources": sorted({row.get("source") for row in analysis.evidence_items if row.get("source")}),
            "source_documents": [
                f"SOURCE: {row.get('source', 'raw')} | TITLE: {row.get('title', '')}"
                for row in analysis.evidence_items[:8]
            ],
            "time_range": {
                "start": self._to_naive_utc(analysis.time_window.start),
                "end": self._to_naive_utc(analysis.time_window.end),
                "days": max(1, (analysis.time_window.end.date() - analysis.time_window.start.date()).days + 1),
            },
            "analysis": {
                "intent_id": analysis.intent_id,
                "time_window": {
                    "start": self._to_naive_utc(analysis.time_window.start),
                    "end": self._to_naive_utc(analysis.time_window.end),
                    "granularity": analysis.time_window.granularity,
                },
                "insights": analysis.insights,
                "patterns": analysis.patterns,
                "limitations": analysis.limitations,
                "confidence": analysis.confidence,
            },
            "analysis_ready": analysis_ready,
            "requires_sources": requires_sources,
            "requirement_reason_codes": reason_codes,
            "required_time_window": required_window_payload,
        }

    def _evaluate_calendar_readiness(
        self,
        *,
        store,
        time_window: TimeWindow,
        now: datetime,
    ) -> Dict[str, object]:
        status = store.get_calendar_feature_status(
            now=self._to_naive_utc(now),
            ttl_hours=self.calendar_ttl_hours,
        )
        reason_codes: List[str] = []

        available = bool(status.get("available"))
        if not available:
            reason_codes.append(REASON_CALENDAR_DATA_MISSING)
        elif not bool(status.get("fresh")):
            reason_codes.append(REASON_CALENDAR_DATA_STALE)

        coverage_start = status.get("coverage_start")
        coverage_end = status.get("coverage_end")
        if coverage_start and coverage_end:
            coverage_start_utc = self._to_aware_utc(coverage_start)
            coverage_end_utc = self._to_aware_utc(coverage_end)
            window_start_utc = self._to_aware_utc(time_window.start)
            window_end_utc = self._to_aware_utc(time_window.end)
            # Feature-store coverage is event-based (sparse), not continuous.
            # Treat as gap only when requested window is fully outside known bounds.
            if window_end_utc < coverage_start_utc or window_start_utc > coverage_end_utc:
                reason_codes.append(REASON_CALENDAR_COVERAGE_GAP)
        elif available:
            reason_codes.append(REASON_CALENDAR_COVERAGE_GAP)

        reason_codes = list(dict.fromkeys(reason_codes))
        return {
            "ready": len(reason_codes) == 0,
            "reason_codes": reason_codes,
            "status": status,
        }

    def _calculate_calendar_specific_day(
        self,
        *,
        events: Sequence[Dict[str, object]],
        window: TimeWindow,
    ) -> AnalysisResult:
        event_rows, limitations = self._collect_calendar_events(events=events, window=window)
        insights = [
            {
                "metric": "event_count",
                "value": len(event_rows),
                "label": "Antal kalenderhändelser",
            }
        ]
        confidence = 0.95 if event_rows else 0.85
        return AnalysisResult(
            intent_id=CALENDAR_SPECIFIC_DAY_INTENT,
            time_window=window,
            insights=insights,
            patterns=[],
            limitations=limitations,
            confidence=confidence,
            evidence_items=[self._to_evidence_item(event, dt) for event, dt in event_rows],
        )

    def _calculate_calendar_least_loaded_day(
        self,
        *,
        events: Sequence[Dict[str, object]],
        window: TimeWindow,
    ) -> AnalysisResult:
        event_rows, limitations = self._collect_calendar_events(events=events, window=window)
        day_counts = self._seed_day_counts(window)

        for _event, dt in event_rows:
            key = dt.date().isoformat()
            if key in day_counts:
                day_counts[key] += 1

        ranked = sorted(day_counts.items(), key=lambda row: (row[1], row[0]))
        best_day, best_count = ranked[0] if ranked else (window.start.date().isoformat(), 0)

        insights = [
            {
                "metric": "least_loaded_day",
                "day": best_day,
                "event_count": best_count,
            }
        ]
        patterns = [
            {
                "metric": "daily_event_counts",
                "values": [{"day": day, "event_count": count} for day, count in sorted(day_counts.items())],
            }
        ]
        confidence = 0.9 if ranked else 0.8
        return AnalysisResult(
            intent_id=CALENDAR_LEAST_LOADED_DAY_INTENT,
            time_window=window,
            insights=insights,
            patterns=patterns,
            limitations=limitations,
            confidence=confidence,
            evidence_items=[self._to_evidence_item(event, dt) for event, dt in event_rows][:8],
        )

    def _collect_calendar_events(
        self,
        *,
        events: Sequence[Dict[str, object]],
        window: TimeWindow,
    ) -> tuple[List[tuple[Dict[str, object], datetime]], List[str]]:
        rows: List[tuple[Dict[str, object], datetime]] = []
        limitations: List[str] = []

        window_start = self._to_local(window.start)
        window_end = self._to_local(window.end)

        for event in events:
            start_at = self._normalized_event_start(event)
            end_at = self._normalized_event_end(event, start_at=start_at)
            if start_at is None:
                limitations.append("Vissa kalenderobjekt saknar tidsfält och kunde inte tolkas.")
                logger.warning("calendar analytics: missing timestamp for event id=%s", event.get("id"))
                continue

            if end_at < start_at:
                limitations.append("Vissa kalenderobjekt har inkonsistent start/slut-tid.")
                logger.warning("calendar analytics: inconsistent event interval id=%s", event.get("id"))
                continue

            if start_at <= window_end and end_at >= window_start:
                rows.append((event, start_at))

        rows.sort(key=lambda row: (row[1], str(row[0].get("title") or "")))
        return rows, list(dict.fromkeys(limitations))

    def _normalized_event_start(self, event: Dict[str, object]) -> Optional[datetime]:
        dt = (
            event.get("start_at")
            or event.get("updated_at")
            or event.get("ingested_at")
            or event.get("last_modified_at")
        )
        if not isinstance(dt, datetime):
            return None
        return self._to_local(dt)

    def _normalized_event_end(self, event: Dict[str, object], *, start_at: Optional[datetime]) -> datetime:
        dt = event.get("end_at")
        if isinstance(dt, datetime):
            return self._to_local(dt)
        return start_at or self._to_local(utcnow())

    @staticmethod
    def _seed_day_counts(window: TimeWindow) -> Dict[str, int]:
        cursor = window.start.date()
        end_date = window.end.date()
        day_counts: Dict[str, int] = {}
        while cursor <= end_date:
            day_counts[cursor.isoformat()] = 0
            cursor = cursor + timedelta(days=1)
        return day_counts

    @staticmethod
    def _limitations_for_reasons(reason_codes: Sequence[str]) -> List[str]:
        mapping = {
            REASON_CALENDAR_DATA_MISSING: "Kalenderdata saknas för perioden.",
            REASON_CALENDAR_DATA_STALE: "Kalenderdata är äldre än 24 timmar.",
            REASON_CALENDAR_COVERAGE_GAP: "Kalenderdata täcker inte hela den efterfrågade perioden.",
        }
        limitations = [mapping[code] for code in reason_codes if code in mapping]
        if not limitations:
            limitations.append("Kalenderdata saknas eller är otillräcklig för analys.")
        return limitations

    @staticmethod
    def _missing_data_narrative(*, reason_codes: Sequence[str], limitations: Sequence[str]) -> str:
        messages: List[str] = []
        if REASON_CALENDAR_DATA_MISSING in reason_codes:
            messages.append("Jag saknar kalenderdata för att kunna analysera frågan.")
        if REASON_CALENDAR_DATA_STALE in reason_codes:
            messages.append("Den kalenderdata som finns är äldre än 24 timmar.")
        if REASON_CALENDAR_COVERAGE_GAP in reason_codes:
            messages.append("Kalenderdata täcker inte hela den period du frågar om.")

        if not messages:
            messages.append("Jag behöver mer kalenderdata innan jag kan ge ett säkert analyssvar.")

        if limitations:
            return " ".join(messages) + "\n\nBegränsningar: " + "; ".join(limitations)
        return " ".join(messages)

    @staticmethod
    def _to_evidence_item(event: Dict[str, object], start_dt: datetime) -> dict:
        notes = str(event.get("notes") or "").strip()
        location = str(event.get("location") or "").strip()
        body_parts = [part for part in [notes, location] if part]
        body = "\n".join(body_parts).strip()
        if len(body) > 280:
            body = body[:279].rstrip() + "…"

        return {
            "id": str(event.get("id") or ""),
            "source": "calendar",
            "type": "event",
            "title": str(event.get("title") or "(Utan titel)").strip() or "(Utan titel)",
            "body": body,
            "date": AnalysisService._to_naive_utc(start_dt),
            "url": None,
        }

    def _render_narrative(self, *, query: str, language: str, analysis: AnalysisResult) -> str:
        analysis_payload = {
            "intent_id": analysis.intent_id,
            "time_window": {
                "start": self._to_naive_utc(analysis.time_window.start).isoformat(),
                "end": self._to_naive_utc(analysis.time_window.end).isoformat(),
                "granularity": analysis.time_window.granularity,
            },
            "insights": analysis.insights,
            "patterns": analysis.patterns,
            "limitations": analysis.limitations,
        }

        prompt = (
            "You are rendering analysis results.\n"
            "You must only use facts from ANALYSIS_JSON.\n"
            "Do not infer missing facts.\n"
            "If insights is empty, explicitly say that no events were found.\n"
            "If limitations exist, include them clearly.\n\n"
            f"USER_QUERY:\n{query}\n\n"
            f"ANALYSIS_JSON:\n{json.dumps(analysis_payload, ensure_ascii=False, indent=2)}\n"
        )

        if self.text_service is not None:
            try:
                generated = self.text_service.generate_text(prompt, max_length=250, language=language)
                if isinstance(generated, dict) and "error" not in generated:
                    text = str(generated.get("generated_text") or "").strip()
                    if text:
                        return text
            except Exception as exc:
                logger.warning("analytics narrative generation failed, using fallback: %s", exc)

        return self._fallback_narrative(analysis)

    @staticmethod
    def _fallback_narrative(analysis: AnalysisResult) -> str:
        limitations_suffix = ""
        if analysis.limitations:
            limitations_suffix = "\n\nBegränsningar: " + "; ".join(analysis.limitations)

        if analysis.intent_id == CALENDAR_SPECIFIC_DAY_INTENT:
            count = 0
            if analysis.insights:
                count = int(analysis.insights[0].get("value", 0) or 0)
            if count == 0:
                return "Jag hittade inga kalenderhändelser i den perioden." + limitations_suffix
            return f"Jag hittade {count} kalenderhändelser i den perioden." + limitations_suffix

        if analysis.intent_id == CALENDAR_LEAST_LOADED_DAY_INTENT and analysis.insights:
            insight = analysis.insights[0]
            day = insight.get("day", "okänd dag")
            count = int(insight.get("event_count", 0) or 0)
            return f"Minst belastade dag är {day} med {count} händelser." + limitations_suffix

        return "Jag kunde inte sammanställa ett analytiskt svar för frågan." + limitations_suffix

    def _to_local(self, dt: datetime) -> datetime:
        return self._to_aware_utc(dt).astimezone(self.temporal_resolver.timezone)

    @staticmethod
    def _to_aware_utc(dt: datetime) -> datetime:
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)

    @staticmethod
    def _to_naive_utc(dt: datetime) -> datetime:
        if dt.tzinfo is None:
            return dt
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
