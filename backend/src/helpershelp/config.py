from __future__ import annotations

import os
from pathlib import Path


BASE_DIR = Path.cwd()

MODEL_CACHE_DIR = Path(
    os.getenv("HELPERSHELP_MODEL_CACHE_DIR", str(BASE_DIR / ".model_cache"))
).expanduser()
DEFAULT_DB_PATH = Path(
    os.getenv("HELPERSHELP_DB_PATH", str(BASE_DIR / "data" / "helpershelp.db"))
).expanduser()
HELPERSHELP_OFFLINE = os.getenv("HELPERSHELP_OFFLINE", "0") == "1"
