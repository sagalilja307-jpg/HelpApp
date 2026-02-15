"""LLM port - abstract interface for text generation"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import List, Optional


class LLMPort(ABC):
    """Abstract interface for LLM text generation"""

    @abstractmethod
    def generate_text(
        self,
        prompt: str,
        max_tokens: Optional[int] = None,
        temperature: float = 0.7,
        system_prompt: Optional[str] = None,
    ) -> str:
        """Generate text from a prompt"""
        pass

    @abstractmethod
    def generate_chat_completion(
        self,
        messages: List[dict],
        max_tokens: Optional[int] = None,
        temperature: float = 0.7,
    ) -> str:
        """Generate text from a chat conversation"""
        pass
