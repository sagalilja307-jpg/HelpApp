"""Backward compatibility shim - imports from application.mail.mail_query_service"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.mail.mail_query_service",
    "helpershelp.application.mail.mail_query_service",
    removal_version="2.0.0"
)

from helpershelp.application.mail.mail_query_service import MailQueryService

__all__ = ["MailQueryService"]
