from __future__ import annotations

import json
import logging

from fastapi import APIRouter, HTTPException, status

from helpershelp.api.deps import (
    embedding_service,
    parse_optional_datetime,
    query_service,
    text_service,
)
from helpershelp.api.models import (
    EmbedBatchRequest,
    EmbedTextRequest,
    FormulateDataRequest,
    FormulateItemsRequest,
    GenerateTextRequest,
    LLMResponse,
    QueryInterpretationRequest,
    SimilarityBatchRequest,
    SimilarityRequest,
)
from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.infrastructure.llm.bge_m3_adapter import EMBEDDING_BACKEND_UNAVAILABLE
from helpershelp.retrieval.content_object import ContentObject, MailSender

logger = logging.getLogger(__name__)

router = APIRouter()


def _raise_if_error(result: dict) -> dict:
    if "error" in result:
        status_code = status.HTTP_400_BAD_REQUEST
        if result.get("error_code") == EMBEDDING_BACKEND_UNAVAILABLE:
            status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        raise HTTPException(
            status_code=status_code,
            detail=result["error"],
        )
    return result


@router.post("/llm/interpret-query", tags=["llm"])
def interpret_query(request: QueryInterpretationRequest):
    result = query_service.interpret_query(request.query, request.language)
    return _raise_if_error(result)


@router.post("/llm/embed", tags=["embedding"])
def embed_text(request: EmbedTextRequest):
    result = embedding_service.embed_text(request.text)
    return _raise_if_error(result)


@router.post("/llm/embed-batch", tags=["embedding"])
def embed_batch(request: EmbedBatchRequest):
    result = embedding_service.embed_batch(request.texts)
    return _raise_if_error(result)


@router.post("/llm/similarity", tags=["embedding"])
def calculate_similarity(request: SimilarityRequest):
    result = embedding_service.similarity(request.text1, request.text2)
    return _raise_if_error(result)


@router.post("/llm/similarity-batch", tags=["embedding"])
def calculate_similarity_batch(request: SimilarityBatchRequest):
    result = embedding_service.similarity_batch(request.query, request.candidates)
    return _raise_if_error(result)


@router.post("/llm/generate", response_model=LLMResponse, tags=["generation"])
def generate_text(request: GenerateTextRequest):
    result = text_service.generate_text(
        request.prompt,
        max_length=request.max_length,
        language=request.language,
    )
    _raise_if_error(result)
    return LLMResponse(content=result.get("generated_text", ""))


@router.post("/llm/formulate", tags=["generation"])
def formulate_data(request: FormulateDataRequest):
    payload = json.dumps(request.data, ensure_ascii=False, indent=2)
    prompt = (
        f"Datatyp: {request.data_type}\n\n"
        f"Data:\n{payload}\n\n"
        "Formulera innehållet tydligt och sakligt på svenska utan att lägga till ny information."
    )
    result = text_service.generate_text(prompt, max_length=300, language="sv")
    _raise_if_error(result)
    return LLMResponse(content=result.get("generated_text", ""))


@router.post("/llm/formulate-items", response_model=LLMResponse, tags=["generation"])
def formulate_items(request: FormulateItemsRequest):
    try:
        items = []
        for item_dict in request.items:
            sender_dict = item_dict.get("sender", {})
            if not isinstance(sender_dict, dict):
                sender_dict = {}

            sender = MailSender(
                address=sender_dict.get("address", "") or "",
                name=sender_dict.get("name"),
                domain=sender_dict.get("domain"),
            )

            content_obj = ContentObject(
                id=item_dict.get("id", ""),
                source=item_dict.get("source", ""),
                subject=item_dict.get("subject", "") or "",
                body=item_dict.get("body", "") or "",
                sender=sender,
                received_at=parse_optional_datetime(item_dict.get("received_at"))
                or utcnow(),
                thread_id=item_dict.get("thread_id"),
                is_replied=item_dict.get("is_replied", False),
            )
            items.append(content_obj)
    except Exception as exc:
        logger.error("Failed to parse items: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid item format: {str(exc)}",
        ) from exc

    result = text_service.formulate_items(
        items=items,
        intent=request.intent,
        language=request.language,
    )
    _raise_if_error(result)
    return LLMResponse(content=result.get("formulated", ""))
