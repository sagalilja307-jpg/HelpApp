import logging
from typing import Optional

from helpershelp.llm.ollama_service import (
    OllamaTextGenerationService,
    get_ollama_text_generation_service
)

logger = logging.getLogger(__name__)


# Backward compatibility alias
# This class now uses Ollama instead of GPT-SW3/llama-cpp
TextGenerationService = OllamaTextGenerationService


# Singleton instance
_text_service: Optional[TextGenerationService] = None


def get_text_generation_service() -> TextGenerationService:
    """Get or create singleton service."""
    global _text_service
    if _text_service is None:
        _text_service = get_ollama_text_generation_service()
    return _text_service
