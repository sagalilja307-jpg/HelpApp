"""Auth port - abstract interface for authentication and authorization"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional


@dataclass
class TokenValidation:
    """Result of token validation"""
    valid: bool
    expires_in: int
    message: Optional[str] = None
    user_id: Optional[str] = None


class AuthPort(ABC):
    """Abstract interface for authentication operations"""

    @abstractmethod
    def validate_token(self, token: str, provider: str = "gmail") -> TokenValidation:
        """Validate an OAuth token"""
        pass

    @abstractmethod
    def refresh_token(self, refresh_token: str, provider: str = "gmail") -> Optional[str]:
        """Refresh an expired token, returns new access token"""
        pass

    @abstractmethod
    def encrypt_token(self, token: str) -> str:
        """Encrypt a token for storage"""
        pass

    @abstractmethod
    def decrypt_token(self, encrypted_token: str) -> str:
        """Decrypt a stored token"""
        pass
