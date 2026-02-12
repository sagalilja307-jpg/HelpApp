from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

_base_from_plan = Path(__file__).resolve().parents[3]
if _base_from_plan.name == "backend":
    BASE_DIR = _base_from_plan
else:
    BASE_DIR = Path(__file__).resolve().parents[2]

MODEL_CACHE_DIR = Path(
    os.getenv("HELPERSHELP_MODEL_CACHE_DIR", str(BASE_DIR / ".model_cache"))
).expanduser()
DEFAULT_DB_PATH = Path(
    os.getenv("HELPERSHELP_DB_PATH", str(BASE_DIR / "data" / "helpershelp.db"))
).expanduser()
HELPERSHELP_OFFLINE = os.getenv("HELPERSHELP_OFFLINE", "0") == "1"

os.environ.setdefault("HF_HUB_DISABLE_IMPLICIT_TOKEN_SUBMISSION", "1")

if HELPERSHELP_OFFLINE:
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
else:
    os.environ.pop("HF_HUB_OFFLINE", None)
    os.environ.pop("TRANSFORMERS_OFFLINE", None)
