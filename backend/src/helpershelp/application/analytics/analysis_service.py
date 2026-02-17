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
from helpershelp.domain.models import UnifiedItem
from helpershelp.domain.value_objects.time_utils import utcnow

logger = logging.getLogger(__name__)


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
    """Analytics-only path for deterministic structured answers (Fas 0.5)."""

    def __init__(
        self,
        *,
        intent_parser: Optional[IntentParser] = None,
        temporal_resolver: Optional[TemporalResolver] = None,
        text_service=None,
    ):
        self.intent_parser = intent_parser or IntentParser()
        self.temporal_resolver = temporal_resolver or TemporalResolver()
        self.text_service = text_service

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

        items = store.list_items(
            since=self._to_naive_utc(time_window.start),
            limit=5000,
        )

        if parsed.intent_id == CALENDAR_SPECIFIC_DAY_INTENT:
            analysis = self._calculate_calendar_specific_day(items=items, window=time_window)
        elif parsed.intent_id == CALENDAR_LEAST_LOADED_DAY_INTENT:
            analysis = self._calculate_calendar_least_loaded_day(items=items, window=time_window)
        else:
            analysis = AnalysisResult(
                intent_id=parsed.intent_id,
                time_window=time_window,
                insights=[],
                patterns=[],
                limitations=["Intent stöds inte i Fas 0.5."],
                confidence=0.0,
                evidence_items=[],
            )

        content = self._render_narrative(query=query, language=language, analysis=analysis)

        return {
            "content": content,
            "evidence_items": analysis.evidence_items,
            "used_sources": sorted({row.get("source") for row in analysis.evidence_items if row.get("source")}),
            "source_documents": [
                f"SOURCE: {row.get('source', 'raw')} | TITLE: {row.get('title', '')}"
                for row in analysis.evidence_items[:8]
            ],
            "time_range": {
                "start": self._to_naive_utc(time_window.start),
                "end": self._to_naive_utc(time_window.end),
                "days": max(1, (time_window.end.date() - time_window.start.date()).days + 1),
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
        }

    def _calculate_calendar_specific_day(self, *, items: Sequence[UnifiedItem], window: TimeWindow) -> AnalysisResult:
        event_rows, limitations = self._collect_calendar_events(items=items, window=window)

        insights = [
            {
                "metric": "event_count",
                "value": len(event_rows),
                "label": "Antal kalenderhändelser",
            }
        ]

        confidence = 0.95 if event_rows else 0.75

        return AnalysisResult(
            intent_id=CALENDAR_SPECIFIC_DAY_INTENT,
            time_window=window,
            insights=insights,
            patterns=[],
            limitations=limitations,
            confidence=confidence,
            evidence_items=[self._to_evidence_item(item, dt) for item, dt in event_rows],
        )

    def _calculate_calendar_least_loaded_day(self, *, items: Sequence[UnifiedItem], window: TimeWindow) -> AnalysisResult:
        event_rows, limitations = self._collect_calendar_events(items=items, window=window)

        day_cursor = window.start.date()
        day_counts: Dict[str, int] = {}
        while day_cursor <= window.end.date():
            day_counts[day_cursor.isoformat()] = 0
            day_cursor = day_cursor + timedelta(days=1)

        for _item, dt in event_rows:
            key = dt.date().isoformat()
            if key in day_counts:
                day_counts[key] += 1

        if day_counts:
            ranked = sorted(day_counts.items(), key=lambda row: (row[1], row[0]))
            best_day, best_count = ranked[0]
        else:
            best_day = window.start.date().isoformat()
            best_count = 0

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
                "values": [
                    {"day": day, "event_count": count}
                    for day, count in sorted(day_counts.items())
                ],
            }
        ]

        confidence = 0.9 if day_counts else 0.7

        return AnalysisResult(
            intent_id=CALENDAR_LEAST_LOADED_DAY_INTENT,
            time_window=window,
            insights=insights,
            patterns=patterns,
            limitations=limitations,
            confidence=confidence,
            evidence_items=[self._to_evidence_item(item, dt) for item, dt in event_rows][:8],
        )

    def _collect_calendar_events(
        self,
        *,
        items: Sequence[UnifiedItem],
        window: TimeWindow,
    ) -> tuple[List[tuple[UnifiedItem, datetime]], List[str]]:
        rows: List[tuple[UnifiedItem, datetime]] = []
        limitations: List[str] = []

        for item in items:
            if not self._is_calendar_event(item):
                continue

            event_time = self._normalized_event_time(item)
            if event_time is None:
                limitations.append("Vissa kalenderobjekt saknar tidsfält och kunde inte tolkas.")
                logger.warning("calendar analytics: missing timestamp for item id=%s source=%s", item.id, item.source)
                continue

            if item.end_at and item.start_at and item.end_at < item.start_at:
                limitations.append("Vissa kalenderobjekt har inkonsistent start/slut-tid.")
                logger.warning("calendar analytics: inconsistent event interval id=%s", item.id)

            if window.start <= event_time <= window.end:
                rows.append((item, event_time))

        rows.sort(key=lambda row: (row[1], row[0].title or ""))
        limitations = list(dict.fromkeys(limitations))
        return rows, limitations

    @staticmethod
    def _is_calendar_event(item: UnifiedItem) -> bool:
        item_type = getattr(getattr(item, "type", None), "value", None) or str(getattr(item, "type", "") or "")
        source = (item.source or "").strip().lower()
        return item_type == "event" or source in {"calendar", "gcal"}

    def _normalized_event_time(self, item: UnifiedItem) -> Optional[datetime]:
        dt = item.start_at or item.updated_at or item.created_at
        if not dt:
            return None

        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(self.temporal_resolver.timezone)

    @staticmethod
    def _to_naive_utc(dt: datetime) -> datetime:
        if dt.tzinfo is None:
            return dt
        return dt.astimezone(timezone.utc).replace(tzinfo=None)

    @staticmethod
    def _to_evidence_item(item: UnifiedItem, dt: datetime) -> dict:
        body = (item.body or "").strip()
        if len(body) > 280:
            body = body[:279].rstrip() + "…"
        return {
            "id": str(item.id),
            "source": "calendar",
            "type": "event",
            "title": (item.title or "(Utan titel)").strip() or "(Utan titel)",
            "body": body,
            "date": AnalysisService._to_naive_utc(dt),
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
                if isinstance(generated, dict):
                    if "error" not in generated:
                        text = (generated.get("generated_text") or "").strip()
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
