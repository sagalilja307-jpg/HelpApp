from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    base_dir: Path
    model_cache_dir: Path
    db_path: Path
    offline: bool


def load_settings() -> Settings:
    # Load .env only when settings are explicitly requested
    from dotenv import load_dotenv
    load_dotenv()
    
    # Try to determine base_dir from environment variable first,
    # fall back to file location as a reasonable default
    base_dir_env = os.getenv("HELPERSHELP_BASE_DIR")
    if base_dir_env:
        base_dir = Path(base_dir_env).expanduser().resolve()
    else:
        # Default: assume we're in helpershelp/infrastructure/config/settings.py
        # and go up 3 levels to reach the backend/src directory
        base_dir = Path(__file__).resolve().parents[3]

    model_cache_dir = Path(
        os.getenv("HELPERSHELP_MODEL_CACHE_DIR", base_dir / ".model_cache")
    ).expanduser()

    db_path = Path(
        os.getenv("HELPERSHELP_DB_PATH", base_dir / "data" / "helpershelp.db")
    ).expanduser()

    offline = os.getenv("HELPERSHELP_OFFLINE", "0") == "1"

    return Settings(
        base_dir=base_dir,
        model_cache_dir=model_cache_dir,
        db_path=db_path,
        offline=offline,
    )


# Cached singleton instance to avoid repeated calls
_settings_instance: Settings | None = None


def get_settings() -> Settings:
    """Get cached settings instance, loading on first call."""
    global _settings_instance
    if _settings_instance is None:
        _settings_instance = load_settings()
    return _settings_instance
