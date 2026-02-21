"""Backward compatibility shim - imports from infrastructure.security.oauth_adapter"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.mail.oauth_service",
    "helpershelp.auth.oauth_adapter",
    removal_version="2.0.0"
)

from helpershelp.auth.oauth_adapter import OAuthService

__all__ = ["OAuthService"]
