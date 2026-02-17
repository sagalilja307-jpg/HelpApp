from __future__ import annotations

import logging
from datetime import timedelta
from typing import Callable, Dict, List, Optional

from fastapi import HTTPException, status

from helpershelp.application.analytics.analysis_service import AnalysisService
from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.infrastructure.llm.bge_m3_adapter import (
    EMBEDDING_BACKEND_UNAVAILABLE,
    EmbeddingBackendUnavailableError,
)
from helpershelp.retrieval.retrieval_coordinator import (
    RetrievalInterpretation,
    get_retrieval_coordinator,
)

logger = logging.getLogger(__name__)


class QueryOrchestrator:
    """
    IMPORTANT:
    Analytics-path and Retrieval-path must never call each other.
    Dispatcher is the only routing layer.
    """

    def __init__(
        self,
        *,
        query_service,
        text_service,
        analysis_service: AnalysisService,
        assistant_store_getter: Callable,
        assistant_store_fetcher: Callable,
        mail_fetcher: Callable,
    ):
        self.query_service = query_service
        self.text_service = text_service
        self.analysis_service = analysis_service
        self._get_store = assistant_store_getter
        self._assistant_store_fetcher = assistant_store_fetcher
        self._mail_fetcher = mail_fetcher

    async def handle(
        self,
        *,
        user_query: str,
        language: str,
        sources: Optional[List[str]],
        days: int,
        data_filter: Optional[dict],
    ) -> Dict:
        parsed_intent = self.analysis_service.parse_intent(user_query)

        if parsed_intent:
            self._audit_dispatch(path="analytics", intent_id=parsed_intent.intent_id)
            return self.analysis_service.handle(
                query=user_query,
                language=language,
                store=self._get_store(),
            )

        self._audit_dispatch(path="retrieval", intent_id=None)
        return self._handle_retrieval(
            user_query=user_query,
            language=language,
            sources=sources,
            days=days,
            data_filter=data_filter,
        )

    def _handle_retrieval(
        self,
        *,
        user_query: str,
        language: str,
        sources: Optional[List[str]],
        days: int,
        data_filter: Optional[dict],
    ) -> Dict:
        now = utcnow()

        interpretation_result = self.query_service.interpret_query(user_query, language)
        if "error" in interpretation_result:
            status_code = status.HTTP_400_BAD_REQUEST
            if interpretation_result.get("error_code") == EMBEDDING_BACKEND_UNAVAILABLE:
                status_code = status.HTTP_503_SERVICE_UNAVAILABLE
            raise HTTPException(status_code=status_code, detail=interpretation_result["error"])

        logger.info(
            "Intent: %s, Topic: %s",
            interpretation_result.get("intent"),
            interpretation_result.get("topic"),
        )

        requested_sources = sources or ["assistant_store"]
        time_range = {"days": days} if days else None

        coordinator = get_retrieval_coordinator()

        if "email" in requested_sources and "email" not in coordinator.source_fetchers:
            coordinator.register_source("email", self._mail_fetcher)
        if "assistant_store" in requested_sources and "assistant_store" not in coordinator.source_fetchers:
            coordinator.register_source("assistant_store", self._assistant_store_fetcher)

        unregistered_sources = [
            source for source in requested_sources if source not in coordinator.source_fetchers
        ]
        if unregistered_sources:
            logger.warning("Unregistered sources requested: %s", unregistered_sources)

        active_sources = [source for source in requested_sources if source in coordinator.source_fetchers]
        if not active_sources:
            return {
                "content": (
                    "Inga sökkällor är registrerade för din fråga. "
                    f"Oregistrerade källor: {', '.join(unregistered_sources)}."
                )
            }

        retrieval_interp = RetrievalInterpretation(
            intent=interpretation_result.get("intent", "summary"),
            sources=active_sources,
            topic_hint=user_query,
            time_range=time_range,
            context={"language": language},
            data_filter=data_filter,
        )
        try:
            retrieved_items = coordinator.retrieve(retrieval_interp)
        except EmbeddingBackendUnavailableError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=str(exc),
            ) from exc

        logger.info("Retrieved %s items", len(retrieved_items))
        if not retrieved_items:
            return {
                "content": (
                    "Jag hittade ingen relevant information att svara på denna fråga. "
                    "Det kan bero på att det inte finns några matchande data eller att "
                    "tidsperioden är för långt tillbaka."
                )
            }

        evidence_items: List[dict] = []
        used_sources = sorted(
            {
                str(item.source)
                for item in retrieved_items
                if getattr(item, "source", None)
            }
        )
        store = self._get_store()
        coverage: dict[str, int] = {}
        for source in used_sources:
            coverage[source] = coverage.get(source, 0) + 1
        store.audit(
            "query_source_coverage",
            {
                "used_sources": used_sources,
                "evidence_items": len(retrieved_items),
                "coverage": coverage,
            },
        )

        for item in retrieved_items[:8]:
            src = str(getattr(item, "source", "") or "raw")
            if src not in {
                "email",
                "calendar",
                "reminders",
                "notes",
                "tasks",
                "contacts",
                "photos",
                "files",
                "locations",
            }:
                src = "raw"

            inferred_type: Optional[str] = None
            if src == "email":
                inferred_type = "email"
            elif src == "calendar":
                inferred_type = "event"
            elif src == "reminders":
                inferred_type = "reminder"
            elif src == "notes":
                inferred_type = "note"
            elif src == "tasks":
                inferred_type = "task"
            elif src == "contacts":
                inferred_type = "contact"
            elif src == "photos":
                inferred_type = "photo"
            elif src == "files":
                inferred_type = "file"
            elif src == "locations":
                inferred_type = "location"

            title = str(getattr(item, "subject", "") or "").strip()
            body = str(getattr(item, "body", "") or "").strip()
            if len(body) > 280:
                body = body[:279].rstrip() + "…"

            dt = getattr(item, "received_at", None)
            url = None
            if src == "email":
                thread_id = getattr(item, "thread_id", None)
                if thread_id:
                    url = f"https://mail.google.com/mail/u/0/#all/{thread_id}"

            evidence_items.append(
                {
                    "id": str(getattr(item, "id", "")),
                    "source": src,
                    "type": inferred_type,
                    "title": title or "(Utan titel)",
                    "body": body,
                    "date": dt,
                    "url": url,
                }
            )

        result = self.text_service.formulate_items(
            items=retrieved_items,
            intent=interpretation_result.get("intent", "summary").upper(),
            language=language,
        )
        if "error" in result:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Formulation failed: {result['error']}",
            )

        logger.info(
            "Generated response from %s items, sources: %s",
            len(retrieved_items),
            result.get("sources", []),
        )

        requested_days = int(days or 90)
        requested_days = max(1, min(3650, requested_days))
        since = now - timedelta(days=requested_days)

        source_documents = [
            f"SOURCE: {getattr(item, 'source', 'raw')} | TITLE: {getattr(item, 'subject', '')}"
            for item in retrieved_items[:8]
        ]

        return {
            "content": result.get("formulated", ""),
            "source_documents": source_documents,
            "evidence_items": evidence_items,
            "used_sources": used_sources,
            "time_range": {
                "start": since,
                "end": now,
                "days": requested_days,
            },
        }

    def _audit_dispatch(self, *, path: str, intent_id: Optional[str]) -> None:
        try:
            self._get_store().audit(
                "query_dispatch_decision",
                {
                    "path": path,
                    "intent_id": intent_id,
                },
            )
        except Exception as exc:
            logger.warning("failed to audit query dispatch decision: %s", exc)
