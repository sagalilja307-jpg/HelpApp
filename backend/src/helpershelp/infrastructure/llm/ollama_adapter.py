# backend/src/helpershelp/infrastructure/llm/ollama_adapter.py
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Dict, Optional

try:
    import requests
except ImportError:  # pragma: no cover
    requests = None


class OllamaUnavailable(RuntimeError):
    """Raised when Ollama is not reachable or requests is missing."""


@dataclass(frozen=True)
class OllamaConfig:
    host: str

    @staticmethod
    def from_env() -> "OllamaConfig":
        return OllamaConfig(host=os.getenv("OLLAMA_HOST", "http://localhost:11434"))


class OllamaClient:
    def __init__(self, config: Optional[OllamaConfig] = None):
        self.config = config or OllamaConfig.from_env()

        if requests is None:
            raise OllamaUnavailable("requests library not available")

    def get_tags(self, timeout_s: int = 5) -> Dict[str, Any]:
        try:
            resp = requests.get(f"{self.config.host}/api/tags", timeout=timeout_s)
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:
            raise OllamaUnavailable(f"Failed to reach Ollama /api/tags: {exc}") from exc

    def post_json(self, path: str, payload: Dict[str, Any], timeout_s: int = 60) -> Dict[str, Any]:
        try:
            resp = requests.post(f"{self.config.host}{path}", json=payload, timeout=timeout_s)
        except Exception as exc:
            raise OllamaUnavailable(f"Failed to reach Ollama {path}: {exc}") from exc

        # Let caller decide how to handle status codes, but give details.
        if resp.status_code < 200 or resp.status_code >= 300:
            preview = (resp.text or "")[:500]
            raise OllamaUnavailable(f"Ollama {path} failed ({resp.status_code}): {preview}")

        try:
            return resp.json()
        except Exception as exc:
            raise OllamaUnavailable(f"Invalid JSON from Ollama {path}: {exc}") from exc
