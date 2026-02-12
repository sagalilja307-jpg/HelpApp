from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


class QueryEvidenceItem(BaseModel):
    id: str
    source: str
    type: Optional[str] = None
    title: str
    body: str
    date: Optional[datetime] = None
    url: Optional[str] = None


class TimeRange(BaseModel):
    start: datetime
    end: datetime
    days: int


class LLMResponse(BaseModel):
    content: str
    confidence: Optional[float] = None
    source_documents: Optional[List[str]] = None
    evidence_items: Optional[List[QueryEvidenceItem]] = None
    used_sources: Optional[List[str]] = None
    time_range: Optional[TimeRange] = None


class QueryInterpretationRequest(BaseModel):
    query: str
    language: str = "en"


class EmbedTextRequest(BaseModel):
    text: str


class EmbedBatchRequest(BaseModel):
    texts: List[str]


class SimilarityRequest(BaseModel):
    text1: str
    text2: str


class SimilarityBatchRequest(BaseModel):
    query: str
    candidates: List[str]


class GenerateTextRequest(BaseModel):
    prompt: str
    max_length: int = 150
    language: str = "sv"


class FormulateDataRequest(BaseModel):
    data_type: str
    data: dict


class FormulateItemsRequest(BaseModel):
    items: List[dict]
    intent: str = "SUMMARY"
    language: str = "sv"


class UnifiedQueryRequest(BaseModel):
    query: str
    language: str = "sv"
    sources: Optional[List[str]] = None
    days: int = 90
    data_filter: Optional[dict] = None
