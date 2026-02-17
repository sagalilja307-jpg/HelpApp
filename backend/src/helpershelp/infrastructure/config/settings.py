from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from dotenv import load_dotenv


# Only load .env once when explicitly imported
load_dotenv()


@dataclass(frozen=True)
class Settings:
    base_dir: Path
    model_cache_dir: Path
    db_path: Path
    offline: bool


def load_settings() -> Settings:
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
