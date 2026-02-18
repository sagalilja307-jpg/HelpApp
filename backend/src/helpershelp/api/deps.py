from __future__ import annotations

from typing import Optional

from helpershelp.application.mail.mail_query_service import MailQueryService
from helpershelp.application.query.data_intent_router import DataIntentRouter
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore, get_store
from helpershelp.infrastructure.security.oauth_adapter import OAuthService
from helpershelp.mail.provider import mail_provider

mail_queries = MailQueryService(mail_provider)
oauth_service = OAuthService()

assistant_store: Optional[SqliteStore] = None
data_intent_router: Optional[DataIntentRouter] = None


def get_assistant_store() -> SqliteStore:
    global assistant_store
    if assistant_store is None:
        assistant_store = get_store()
    return assistant_store


def reset_assistant_store() -> None:
    global assistant_store
    assistant_store = None


def get_data_intent_router() -> DataIntentRouter:
    global data_intent_router
    if data_intent_router is None:
        data_intent_router = DataIntentRouter()
    return data_intent_router
