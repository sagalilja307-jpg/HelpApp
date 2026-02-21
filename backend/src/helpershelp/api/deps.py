from __future__ import annotations

from typing import Optional

from helpershelp.mail.mail_query_service import MailQueryService
from helpershelp.query.data_intent_router import DataIntentRouter
from helpershelp.auth.oauth_adapter import OAuthService
from helpershelp.mail.provider import mail_provider

mail_queries = MailQueryService(mail_provider)
oauth_service = OAuthService()

data_intent_router: Optional[DataIntentRouter] = None


def get_data_intent_router() -> DataIntentRouter:
    global data_intent_router
    if data_intent_router is None:
        data_intent_router = DataIntentRouter()
    return data_intent_router
