"""
Convenience entrypoint for running the FastAPI app.

README refers to `uvicorn api:app --reload`, so expose the app at module root.
"""

import sys
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parent / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from helpershelp.api.app import app  # noqa: F401
