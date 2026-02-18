from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Query

from helpershelp.api.deps import mail_queries
from helpershelp.mail.content_object import ContentObject

router = APIRouter()


@router.get("/mail/unanswered", response_model=List[ContentObject], tags=["mail"])
def get_unanswered_mail(
    since: Optional[str] = Query(default=None),
    limit: int = Query(default=50, le=100),
):
    since_dt = datetime.fromisoformat(since) if since else None
    return mail_queries.unanswered(since=since_dt, max_results=limit)


@router.get("/mail/from-domain", response_model=List[ContentObject], tags=["mail"])
def get_mail_from_domain(
    domain: str,
    limit: int = Query(default=50, le=100),
):
    return mail_queries.from_domain(domain=domain, max_results=limit)


@router.get("/mail/recent", response_model=List[ContentObject], tags=["mail"])
def get_recent_mail(
    days: int = Query(default=7, ge=1),
    limit: int = Query(default=50, le=100),
):
    return mail_queries.recent(days=days, max_results=limit)
