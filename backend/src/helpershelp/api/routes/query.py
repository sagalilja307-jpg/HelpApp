from __future__ import annotations

import logging
from datetime import timedelta
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, model_validator

from helpershelp.api.deps import (
    get_assistant_store,
    assistant_store_fetch,
    mail_queries,
    query_service,
    text_service,
)
from helpershelp.api.models import LLMResponse, QueryEvidenceItem, TimeRange
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

router = APIRouter()


class QueryRequest(BaseModel):
    query: Optional[str] = None
    question: Optional[str] = None
    language: str = "sv"
    sources: Optional[List[str]] = None
    days: int = 90
    data_filter: Optional[dict] = None

    @model_validator(mode="after")
    def validate_input(self):
        if not self.query and not self.question:
            raise ValueError("Either 'query' or 'question' must be provided")
        return self

    @property
    def resolved_query(self) -> str:
        return self.query or self.question or ""


@router.post("/query", response_model=LLMResponse, tags=["query"])
async def unified_query(request: QueryRequest):
    try:
        now = utcnow()
        user_query = request.resolved_query
        logger.info("Processing query: %s", user_query)

        interpretation_result = query_service.interpret_query(
            user_query,
            request.language,
        )
        if "error" in interpretation_result:
            status_code = status.HTTP_400_BAD_REQUEST
            if interpretation_result.get("error_code") == EMBEDDING_BACKEND_UNAVAILABLE:
                status_code = status.HTTP_503_SERVICE_UNAVAILABLE
            raise HTTPException(
                status_code=status_code,
                detail=interpretation_result["error"],
            )

        logger.info(
            "Intent: %s, Topic: %s",
            interpretation_result.get("intent"),
            interpretation_result.get("topic"),
        )

        sources = request.sources or ["assistant_store"]
        time_range = {"days": request.days} if request.days else None

        coordinator = get_retrieval_coordinator()

        if "email" in sources and "email" not in coordinator.source_fetchers:
            coordinator.register_source("email", mail_queries.fetch)
        if "assistant_store" in sources and "assistant_store" not in coordinator.source_fetchers:
            coordinator.register_source("assistant_store", assistant_store_fetch)

        unregistered_sources = [
            source for source in sources if source not in coordinator.source_fetchers
        ]
        if unregistered_sources:
            logger.warning("Unregistered sources requested: %s", unregistered_sources)

        active_sources = [source for source in sources if source in coordinator.source_fetchers]
        if not active_sources:
            return LLMResponse(
                content=(
                    "Inga sökkällor är registrerade för din fråga. "
                    f"Oregistrerade källor: {', '.join(unregistered_sources)}."
                )
            )

        retrieval_interp = RetrievalInterpretation(
            intent=interpretation_result.get("intent", "summary"),
            sources=active_sources,
            topic_hint=user_query,
            time_range=time_range,
            context={"language": request.language},
            data_filter=request.data_filter,
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
            return LLMResponse(
                content=(
                    "Jag hittade ingen relevant information att svara på denna fråga. "
                    "Det kan bero på att det inte finns några matchande data eller att "
                    "tidsperioden är för långt tillbaka."
                )
            )

        evidence_items: List[QueryEvidenceItem] = []
        used_sources = sorted(
            {
                str(item.source)
                for item in retrieved_items
                if getattr(item, "source", None)
            }
        )
        store = get_assistant_store()
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
                QueryEvidenceItem(
                    id=str(getattr(item, "id", "")),
                    source=src,
                    type=inferred_type,
                    title=title or "(Utan titel)",
                    body=body,
                    date=dt,
                    url=url,
                )
            )

        result = text_service.formulate_items(
            items=retrieved_items,
            intent=interpretation_result.get("intent", "summary").upper(),
            language=request.language,
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

        requested_days = int(request.days or 90)
        requested_days = max(1, min(3650, requested_days))
        since = now - timedelta(days=requested_days)

        source_documents = [
            f"SOURCE: {getattr(item, 'source', 'raw')} | TITLE: {getattr(item, 'subject', '')}"
            for item in retrieved_items[:8]
        ]

        return LLMResponse(
            content=result.get("formulated", ""),
            source_documents=source_documents,
            evidence_items=evidence_items,
            used_sources=used_sources,
            time_range=TimeRange(start=since, end=now, days=requested_days),
        )
    except HTTPException:
        raise
    except EmbeddingBackendUnavailableError as exc:
        logger.error("Query processing failed (embedding backend unavailable): %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        logger.error("Query processing failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal error: {str(exc)}",
        ) from exc
