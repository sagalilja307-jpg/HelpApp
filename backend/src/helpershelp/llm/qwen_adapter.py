from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, cast, get_args

from helpershelp.core.config import OLLAMA_MODEL
from helpershelp.query.intent_plan import Domain, Operation

from .ollama_adapter import OllamaClient, OllamaUnavailable

_VALID_DOMAINS = frozenset(get_args(Domain))
_VALID_OPERATIONS = frozenset(get_args(Operation))
_JSON_BLOCK_RE = re.compile(r"\{.*\}", re.DOTALL)
_DEFAULT_FALLBACK_REASON = "Fallback p.g.a tekniskt fel."


@dataclass(frozen=True)
class QwenDomainResult:
    domain: Domain | None
    confidence: float
    ranked: List[tuple[Domain, float]]
    needs_clarification: bool
    suggestions: List[Domain]
    reasoning: str = ""


class QwenClassifier:
    """Qwen2.5 via Ollama for deterministic domain classification."""

    def __init__(
        self,
        ollama: Optional[OllamaClient] = None,
        model: Optional[str] = None,
        request_timeout_seconds: int = 12,
    ):
        self.model = (model or OLLAMA_MODEL or "qwen2.5:7b").strip() or "qwen2.5:7b"
        self.request_timeout_seconds = max(1, int(request_timeout_seconds))
        try:
            self.ollama = ollama or OllamaClient()
        except OllamaUnavailable:
            self.ollama = None

    def _build_prompt(self, text: str) -> str:
        domains = ", ".join(sorted(_VALID_DOMAINS))
        safe_text = json.dumps(text, ensure_ascii=False)
        return f"""Du är en expert på att klassificera användarintent för ett affärssystem.
Analysera följande text och avgör vilken domän den tillhör.

Tillgängliga domäner:
{domains}

Svara EXAKT och ENDAST med ett JSON-objekt i detta format:
{{
  "domain": "DOMÄN_NAMN",
  "confidence": 0.0-1.0,
  "reasoning": "Kort motivering på svenska"
}}

Användarens text: {safe_text}
JSON:"""

    @staticmethod
    def _coerce_confidence(value: Any) -> float:
        try:
            confidence = float(value)
        except (TypeError, ValueError):
            confidence = 0.0
        return max(0.0, min(1.0, confidence))

    @staticmethod
    def _coerce_domain(value: Any) -> Domain | None:
        candidate = str(value or "").strip().lower()
        if candidate in _VALID_DOMAINS:
            return cast(Domain, candidate)
        return None

    @staticmethod
    def _parse_json_block(raw_content: str) -> Dict[str, Any]:
        content = raw_content.strip()
        if not content:
            raise ValueError("Tomt svar från modell")

        # Handle fenced JSON payloads first.
        fenced = re.sub(r"^```(?:json)?\s*|\s*```$", "", content, flags=re.IGNORECASE).strip()
        if fenced:
            try:
                parsed = json.loads(fenced)
                if isinstance(parsed, dict):
                    return cast(Dict[str, Any], parsed)
            except json.JSONDecodeError:
                pass

        # Fallback: extract first JSON-like object from mixed text.
        match = _JSON_BLOCK_RE.search(content)
        if not match:
            raise ValueError(f"Kunde inte hitta JSON i svaret: {content}")

        parsed = json.loads(match.group(0))
        if not isinstance(parsed, dict):
            raise ValueError("Modellsvar innehåller JSON, men inte ett objekt")
        return cast(Dict[str, Any], parsed)

    def _fallback_result(self, *, reason: str = _DEFAULT_FALLBACK_REASON) -> QwenDomainResult:
        return QwenDomainResult(
            domain=None,
            confidence=0.0,
            ranked=[],
            needs_clarification=True,
            suggestions=[],
            reasoning=reason,
        )

    def classify(self, text: str) -> QwenDomainResult:
        query = (text or "").strip()
        if not query:
            return self._fallback_result(reason="Tom fråga.")
        if self.ollama is None:
            return self._fallback_result()

        payload = {
            "model": self.model,
            "prompt": self._build_prompt(query),
            "stream": False,
            "options": {
                "temperature": 0,
                "top_p": 0.9,
            },
        }

        try:
            response = self.ollama.post_json(
                "/api/generate",
                payload,
                timeout_s=self.request_timeout_seconds,
            )
            raw_content = str(response.get("response", "")).strip()
            data = self._parse_json_block(raw_content)
        except (OllamaUnavailable, ValueError, json.JSONDecodeError) as exc:
            return self._fallback_result(reason=f"{_DEFAULT_FALLBACK_REASON} {exc}")

        domain = self._coerce_domain(data.get("domain"))
        confidence = self._coerce_confidence(data.get("confidence"))
        reasoning = str(data.get("reasoning", "")).strip()

        if domain is None:
            return QwenDomainResult(
                domain=None,
                confidence=confidence,
                ranked=[],
                needs_clarification=True,
                suggestions=[],
                reasoning=reasoning,
            )

        return QwenDomainResult(
            domain=domain,
            confidence=confidence,
            ranked=[(domain, confidence)],
            needs_clarification=False,
            suggestions=[],
            reasoning=reasoning,
        )


class QwenFilterStructurer:
    """
    Qwen2.5 via Ollama for filter structuring.

    Returns a best-effort filter dict. Any parse/model error returns {}.
    Strict validation/sanitization is expected to happen in the router layer.
    """

    def __init__(
        self,
        ollama: Optional[OllamaClient] = None,
        model: Optional[str] = None,
        request_timeout_seconds: int = 12,
    ):
        self.model = (model or OLLAMA_MODEL or "qwen2.5:7b").strip() or "qwen2.5:7b"
        self.request_timeout_seconds = max(1, int(request_timeout_seconds))
        try:
            self.ollama = ollama or OllamaClient()
        except OllamaUnavailable:
            self.ollama = None

    def _build_prompt(self, *, query: str, domain: Domain, language: str) -> str:
        safe_query = json.dumps(query, ensure_ascii=False)
        safe_domain = json.dumps(domain, ensure_ascii=False)
        safe_language = json.dumps((language or "sv").strip().lower(), ensure_ascii=False)

        return f"""Du strukturerar filter för en användarfråga.

Regler:
- Svara EXAKT och ENDAST med ett JSON-objekt.
- JSON-format:
{{
  "filters": {{
    "status": null | "unread" | "cancelled" | "completed" | "pending",
    "participants": string[],
    "location": null | string,
    "text_contains": null | string,
    "tags": string[],
    "priority": null | "high" | "medium" | "low",
    "has_attachment": null | true | false,
    "source_account": null | "gmail" | "outlook" | "icloud",
    "subdomain": null | "activity" | "wellbeing",
    "metric": null | "step_count" | "distance" | "exercise_time" | "workout" | "sleep" | "mindful_session" | "state_of_mind" | "heart_rate" | "resting_heart_rate" | "hrv" | "respiratory_rate" | "blood_oxygen",
    "workout_type": null | "running" | "cycling" | "strength",
    "aggregation": null | "sum" | "average" | "count" | "duration"
  }}
}}
- Sätt null eller [] när något inte framgår.
- Hitta inte på värden.

Domän: {safe_domain}
Språk: {safe_language}
Användarfråga: {safe_query}
JSON:"""

    def structure_filters(self, *, query: str, domain: Domain, language: str = "sv") -> Dict[str, Any]:
        normalized_query = (query or "").strip()
        if not normalized_query or self.ollama is None:
            return {}

        payload = {
            "model": self.model,
            "prompt": self._build_prompt(query=normalized_query, domain=domain, language=language),
            "stream": False,
            "options": {
                "temperature": 0,
                "top_p": 0.9,
            },
        }

        try:
            response = self.ollama.post_json(
                "/api/generate",
                payload,
                timeout_s=self.request_timeout_seconds,
            )
            raw_content = str(response.get("response", "")).strip()
            data = QwenClassifier._parse_json_block(raw_content)
        except (OllamaUnavailable, ValueError, json.JSONDecodeError):
            return {}

        if isinstance(data.get("filters"), dict):
            return cast(Dict[str, Any], data.get("filters"))
        if isinstance(data, dict):
            return data
        return {}


class QwenIntentStructurer:
    """
    Qwen2.5 via Ollama for one-shot intent structuring.

    Returns a best-effort intent dict. Any parse/model error returns {}.
    Strict validation/sanitization is expected in the router layer.
    """

    def __init__(
        self,
        ollama: Optional[OllamaClient] = None,
        model: Optional[str] = None,
        request_timeout_seconds: int = 12,
    ):
        self.model = (model or OLLAMA_MODEL or "qwen2.5:7b").strip() or "qwen2.5:7b"
        self.request_timeout_seconds = max(1, int(request_timeout_seconds))
        try:
            self.ollama = ollama or OllamaClient()
        except OllamaUnavailable:
            self.ollama = None

    def _build_prompt(self, *, query: str, language: str) -> str:
        domains = ", ".join(sorted(_VALID_DOMAINS))
        operations = ", ".join(sorted(_VALID_OPERATIONS))
        safe_query = json.dumps(query, ensure_ascii=False)
        safe_language = json.dumps((language or "sv").strip().lower(), ensure_ascii=False)

        return f"""Du tolkar användarfrågor till ett intent-objekt.

Regler:
- Svara EXAKT och ENDAST med ett JSON-objekt.
- JSON-format:
{{
  "domain": null | "{'" | "'.join(sorted(_VALID_DOMAINS))}",
  "operation": null | "{'" | "'.join(sorted(_VALID_OPERATIONS))}",
  "filters": {{
    "status": null | "unread" | "cancelled" | "completed" | "pending",
    "participants": string[],
    "location": null | string,
    "text_contains": null | string,
    "tags": string[],
    "priority": null | "high" | "medium" | "low",
    "has_attachment": null | true | false,
    "source_account": null | "gmail" | "outlook" | "icloud",
    "subdomain": null | "activity" | "wellbeing",
    "metric": null | "step_count" | "distance" | "exercise_time" | "workout" | "sleep" | "mindful_session" | "state_of_mind" | "heart_rate" | "resting_heart_rate" | "hrv" | "respiratory_rate" | "blood_oxygen",
    "workout_type": null | "running" | "cycling" | "strength",
    "aggregation": null | "sum" | "average" | "count" | "duration"
  }}
}}
- Hitta inte på nya domäner eller operationer.
- Om osäker, använd null för domain/operation och tomma filter.

Tillåtna domäner: {domains}
Tillåtna operationer: {operations}
Språk: {safe_language}
Användarfråga: {safe_query}
JSON:"""

    def structure_intent(self, *, query: str, language: str = "sv") -> Dict[str, Any]:
        normalized_query = (query or "").strip()
        if not normalized_query or self.ollama is None:
            return {}

        payload = {
            "model": self.model,
            "prompt": self._build_prompt(query=normalized_query, language=language),
            "stream": False,
            "options": {
                "temperature": 0,
                "top_p": 0.9,
            },
        }

        try:
            response = self.ollama.post_json(
                "/api/generate",
                payload,
                timeout_s=self.request_timeout_seconds,
            )
            raw_content = str(response.get("response", "")).strip()
            data = QwenClassifier._parse_json_block(raw_content)
        except (OllamaUnavailable, ValueError, json.JSONDecodeError):
            return {}

        if isinstance(data.get("intent"), dict):
            return cast(Dict[str, Any], data.get("intent"))
        if isinstance(data, dict):
            return data
        return {}


_qwen_classifier: Optional[QwenClassifier] = None
_qwen_filter_structurer: Optional[QwenFilterStructurer] = None
_qwen_intent_structurer: Optional[QwenIntentStructurer] = None


def get_qwen_classifier() -> QwenClassifier:
    global _qwen_classifier
    if _qwen_classifier is None:
        _qwen_classifier = QwenClassifier()
    return _qwen_classifier


def get_qwen_filter_structurer() -> QwenFilterStructurer:
    global _qwen_filter_structurer
    if _qwen_filter_structurer is None:
        _qwen_filter_structurer = QwenFilterStructurer()
    return _qwen_filter_structurer


def get_qwen_intent_structurer() -> QwenIntentStructurer:
    global _qwen_intent_structurer
    if _qwen_intent_structurer is None:
        _qwen_intent_structurer = QwenIntentStructurer()
    return _qwen_intent_structurer
