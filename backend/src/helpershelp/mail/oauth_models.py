from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class OAuthToken(BaseModel):
    """OAuth token contract."""
    access_token: str
    refresh_token: Optional[str] = None
    expires_in: int
    token_type: str = "Bearer"
    
    class Config:
        json_schema_extra = {
            "example": {
                "access_token": "ya29.a0AfH6SMBx...",
                "refresh_token": "1//0gF...",
                "expires_in": 3600,
                "token_type": "Bearer"
            }
        }


class TokenValidationRequest(BaseModel):
    """Validate incoming token from app."""
    access_token: str
    provider: str = Field(default="gmail", description="Mail provider: gmail, icloud, etc")


class TokenValidationResponse(BaseModel):
    """Response after validation."""
    valid: bool
    access_token: str
    refresh_token: Optional[str] = None
    expires_in: int
    token_type: str = "Bearer"
    expires_at: Optional[datetime] = None
    message: Optional[str] = None


class TokenRefreshRequest(BaseModel):
    """Request to refresh expired token."""
    refresh_token: str
    provider: str = Field(default="gmail")
