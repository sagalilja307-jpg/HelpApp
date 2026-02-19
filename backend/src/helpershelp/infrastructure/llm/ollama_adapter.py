from __future__ import annotations

from typing import Any, Dict

from helpershelp.config import OLLAMA_HOST

try:
    import requests
except ImportError:  # pragma: no cover
    requests = None


class OllamaUnavailable(RuntimeError):
    """Raised when Ollama is not reachable or requests is missing."""


class OllamaClient:
    """Minimal Ollama HTTP client (GET/POST JSON)."""

    def __init__(self, host: str | None = None):
        if requests is None:
            raise OllamaUnavailable("requests library not available")

        self.host = (host or OLLAMA_HOST).rstrip("/")
        self._session = requests.Session()

    def _url(self, path: str) -> str:
        p = path if path.startswith("/") else f"/{path}"
        return f"{self.host}{p}"

    def get_json(self, path: str, *, timeout_s: int = 10) -> Dict[str, Any]:
        url = self._url(path)
        try:
            resp = self._session.get(url, timeout=timeout_s)
        except Exception as exc:
            raise OllamaUnavailable(f"Failed to reach Ollama GET {path}: {exc}") from exc

        if not (200 <= resp.status_code < 300):
            preview = (resp.text or "")[:500]
            raise OllamaUnavailable(f"Ollama GET {path} failed ({resp.status_code}): {preview}")

        try:
            return resp.json()
        except Exception as exc:
            raise OllamaUnavailable(f"Invalid JSON from Ollama GET {path}: {exc}") from exc

    def post_json(self, path: str, payload: Dict[str, Any], *, timeout_s: int = 60) -> Dict[str, Any]:
        url = self._url(path)
        try:
            resp = self._session.post(url, json=payload, timeout=timeout_s)
        except Exception as exc:
            raise OllamaUnavailable(f"Failed to reach Ollama POST {path}: {exc}") from exc

        if not (200 <= resp.status_code < 300):
            preview = (resp.text or "")[:500]
            raise OllamaUnavailable(f"Ollama POST {path} failed ({resp.status_code}): {preview}")

        try:
            return resp.json()
        except Exception as exc:
            raise OllamaUnavailable(f"Invalid JSON from Ollama POST {path}: {exc}") from exc

    def get_tags(self, *, timeout_s: int = 5) -> Dict[str, Any]:
        return self.get_json("/api/tags", timeout_s=timeout_s)
