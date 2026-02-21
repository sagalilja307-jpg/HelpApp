from __future__ import annotations

import os
from pathlib import Path


BASE_DIR = Path.cwd()

DEFAULT_DB_PATH = Path(
    os.getenv("HELPERSHELP_DB_PATH", str(BASE_DIR / "data" / "helpershelp.db"))
).expanduser()
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:7b")
OLLAMA_EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL", "bge-m3")
