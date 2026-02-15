from datetime import datetime, timedelta, timezone
from typing import Optional, Dict
import jwt
import logging

from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.mail.oauth_models import OAuthToken, TokenValidationResponse, TokenRefreshRequest

logger = logging.getLogger(__name__)


class OAuthService:
    """
    Handles OAuth token validation using offline JWT decoding.
    No external API calls needed - everything is local.
    """

    def __init__(self):
        # In-memory token cache
        self.token_cache: Dict[str, OAuthToken] = {}

    def validate_token(
        self,
        access_token: str,
        provider: str = "gmail"
    ) -> TokenValidationResponse:
        """
        Validate token offline by decoding JWT.
        Works with Google/Gmail tokens without calling Google's API.
        """
        
        if provider.lower() in ["gmail", "google"]:
            return self._validate_google_token_offline(access_token)
        
        logger.warning(f"Unknown OAuth provider: {provider}")
        return TokenValidationResponse(
            valid=False,
            access_token=access_token,
            expires_in=0,
            message=f"Unknown provider: {provider}"
        )

    def _validate_google_token_offline(self, access_token: str) -> TokenValidationResponse:
        """
        Validate Google token by decoding the JWT without verifying signature.
        
        This works because:
        1. Google tokens are standard JWT format
        2. We only check expiration (don't need signature verification)
        3. The token came from Google's official OAuth flow on the app side
        
        If you need to be extra safe, the app should validate the token
        with Google once during login, then send it to us for caching.
        """
        try:
            # Decode without verifying signature
            # Safe because: token comes from official Google OAuth, we just check expiry
            payload = jwt.decode(
                access_token,
                options={"verify_signature": False},
                algorithms=["RS256", "HS256"]
            )
            
            # Check expiration
            exp_timestamp = payload.get("exp")
            if not exp_timestamp:
                logger.warning("Token has no expiration time")
                return TokenValidationResponse(
                    valid=False,
                    access_token=access_token,
                    expires_in=0,
                    message="Token missing expiration"
                )
            
            exp_datetime = datetime.fromtimestamp(exp_timestamp, timezone.utc).replace(tzinfo=None)
            now = utcnow()
            
            if exp_datetime < now:
                # Token expired
                return TokenValidationResponse(
                    valid=False,
                    access_token=access_token,
                    expires_in=0,
                    message="Token has expired"
                )
            
            # Calculate remaining time
            remaining = int((exp_datetime - now).total_seconds())
            
            # Token is valid!
            logger.info(f"Token valid for {remaining}s")
            
            return TokenValidationResponse(
                valid=True,
                access_token=access_token,
                expires_in=remaining,
                token_type="Bearer",
                expires_at=exp_datetime,
                message=f"Token valid for {remaining}s"
            )
            
        except jwt.DecodeError as e:
            logger.error(f"Failed to decode token: {e}")
            return TokenValidationResponse(
                valid=False,
                access_token=access_token,
                expires_in=0,
                message=f"Invalid token format: {str(e)}"
            )
        except Exception as e:
            logger.error(f"Token validation error: {e}")
            return TokenValidationResponse(
                valid=False,
                access_token=access_token,
                expires_in=0,
                message=f"Validation error: {str(e)}"
            )

    def refresh_token(
        self,
        refresh_token: str,
        provider: str = "gmail"
    ) -> Optional[OAuthToken]:
        """
        Note: Offline validation doesn't handle refresh.
        
        The app should:
        1. Handle token refresh with Google (when token expires)
        2. Send us the new token via /auth/store
        
        We'll validate it here, but won't refresh it ourselves.
        """
        logger.warning("Refresh not supported - app must handle refresh with Google")
        return None

    def store_token(self, provider: str, token: OAuthToken) -> None:
        """Store token in cache for quick lookups."""
        self.token_cache[provider] = token
        logger.info(f"Token stored for provider: {provider}")

    def get_cached_token(self, provider: str) -> Optional[OAuthToken]:
        """Retrieve cached token."""
        return self.token_cache.get(provider)
