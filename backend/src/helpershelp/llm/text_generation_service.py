import logging
import sys
from datetime import datetime
import os
from pathlib import Path
from typing import Dict, Optional, List

from helpershelp.retrieval.content_object import ContentObject
from helpershelp.config import MODEL_CACHE_DIR

try:
    from llama_cpp import Llama
except Exception:  # pragma: no cover - optional dependency
    Llama = None

logger = logging.getLogger(__name__)


class TextGenerationService:
    """
    GPT-SWE3 formulation service.
    
    ONLY formulates and summarizes already-retrieved information.
    Does NOT search, interpret, or make assumptions.
    """

    # SYSTEM PROMPT (statisk, aldrig ändrad)
    SYSTEM_PROMPT = """Du är en språkassistent som endast formulerar och sammanfattar information
som redan har valts ut av systemet.

VIKTIGT:
- Du får inte lägga till ny information.
- Du får inte anta något som inte explicit finns i underlaget.
- Du får inte väga vad som är viktigast – urvalet är redan gjort.
- Om information saknas eller är oklar ska du säga det tydligt.

Du ska:
- skriva på korrekt, tydlig svenska
- vara neutral och saklig
- strukturera texten så den är lätt att läsa
- spegla innehållet utan att tolka bort eller förstärka

Om flera källor motsäger varandra:
- redovisa detta neutralt
- dra inga egna slutsatser

Du är inte rådgivande om det inte uttryckligen efterfrågas."""

    def __init__(self):
        """Initialize GPT-SWE3 model (local GGUF via llama-cpp)."""
        self.model = None
        self.model_available = False
        
        try:
            logger.info("[TextGenerationService] Loading GPT-SWE3 model...")

            allow_unsupported = os.getenv("GPT_SW3_ALLOW_UNSUPPORTED_PYTHON", "0") == "1"
            if sys.version_info >= (3, 13) and not allow_unsupported:
                logger.warning(
                    "Unsupported Python version for llama-cpp-python. "
                    "Use Python 3.11/3.12 or set GPT_SW3_ALLOW_UNSUPPORTED_PYTHON=1 to force."
                )
                return

            default_path = MODEL_CACHE_DIR / "gguf" / "gpt-sw3-126m-instruct-f16.gguf"
            model_path = os.getenv(
                "GPT_SW3_GGUF_PATH",
                str(default_path)
            )

            if Llama is None:
                logger.warning("llama-cpp-python is not installed - text generation will use placeholder mode")
                return

            if not Path(model_path).exists():
                logger.warning(f"GPT-SWE3 model not found at: {model_path} - using placeholder mode")
                return

            self.model = Llama(
                model_path=model_path,
                n_ctx=4096,
                n_threads=os.cpu_count() or 4
            )
            self.model_available = True
            logger.info("✅ GPT-SWE3 GGUF model loaded successfully")

        except Exception as e:
            logger.warning(f"⚠️  GPT-SWE3 model loading failed: {e} - using placeholder mode")
            self.model = None
            self.model_available = False

    def formulate_items(
        self,
        items: List[ContentObject],
        intent: str = "SUMMARY",
        language: str = "sv"
    ) -> Dict:
        """
        Formulate already-retrieved items into natural language.
        
        Args:
            items: List of ContentObjects (already filtered by retrieval)
            intent: What to do with them (SUMMARY, OVERVIEW, STATUS)
            language: Output language (sv, en)
        
        Returns:
            {
                "formulated": "Generated text",
                "intent": "SUMMARY",
                "items_count": 3,
                "sources": ["email", "memory"]
            }
        """
        
        if not items:
            return {"error": "No items to formulate"}
        
        if not self.model_available:
            # Placeholder mode - return extracted content
            logger.warning("Using placeholder formulation mode (model not available)")
            return self._placeholder_formulation(items, intent)
        
        # Build content blocks from items
        content_blocks = self._build_content_blocks(items)
        
        # Build input prompt
        prompt = self._build_input_prompt(
            content_blocks=content_blocks,
            intent=intent,
            language=language
        )
        
        try:
            full_prompt = f"{self.SYSTEM_PROMPT}\n\n{prompt}"
            generated = self._generate(full_prompt, max_tokens=500)
            stripped = self._strip_prompt_echo(generated)

            if not stripped:
                return self._placeholder_formulation(items, intent)

            return {
                "formulated": stripped,
                "intent": intent,
                "items_count": len(items),
                "sources": list(set(item.source for item in items))
            }
        except Exception as e:
            logger.error(f"Formulation failed: {e}")
            return self._placeholder_formulation(items, intent)

    def _build_content_blocks(self, items: List[ContentObject]) -> str:
        """
        Build structured content blocks for GPT-SW3.
        
        Format:
        [KÄLLA: EMAIL]
        Datum: 2024-11-03
        Innehål:
        "Text..."
        
        ---
        
        [KÄLLA: MEMORY]
        ...
        """
        
        blocks = []
        
        for item in items:
            source_name = item.source.upper()
            
            # Format date if available
            date_str = ""
            if hasattr(item, 'received_at') and item.received_at:
                received_at = item.received_at
                if isinstance(received_at, str):
                    try:
                        received_at = datetime.fromisoformat(received_at.replace("Z", "+00:00"))
                    except ValueError:
                        received_at = None
                if received_at:
                    date_str = f"Datum: {received_at.isoformat()}\n"
            
            # Get content
            content = item.body or item.subject or ""
            
            # Build block
            block = (
                f"[KÄLLA: {source_name}]\n"
                f"{date_str}Innehål:\n"
                f"\"{content.strip()}\""
            )
            
            blocks.append(block)
        
        return "\n\n---\n\n".join(blocks)

    def _build_input_prompt(
        self,
        content_blocks: str,
        intent: str,
        language: str
    ) -> str:
        """
        Build input prompt for GPT-SW3.
        
        This is the dynamic part (changes per request).
        System prompt is constant.
        """
        
        intent_sv = {
            "SUMMARY": "SAMMANFATTNING",
            "OVERVIEW": "ÖVERSIKT",
            "STATUS": "STATUS",
            "TIMELINE": "TIDSLINJE"
        }.get(intent, intent)
        
        prompt = f"""UPPGIFT:
Sammanfatta innehållet nedan enligt instruktionerna.

INTENT:
{intent_sv}

SPRÅK:
Svenska

UNDERLAG:
Nedanstående information är redan filtrerad och utvald av systemet.
Du ska endast använda detta innehål.
Skriv endast själva svaret efter "SVAR:" och upprepa inte underlaget.

BEGIN CONTENT
{content_blocks}
END CONTENT

SVAR:
"""
        
        return prompt

    def generate_text(self, prompt: str, max_length: int = 150, language: str = "sv") -> Dict:
        """
        Legacy: Generate text from arbitrary prompt.
        
        ⚠️ This bypasses the safety structure above.
        Only use for simple text generation, not data formulation.
        """
        
        if not prompt or not prompt.strip():
            return {"error": "Empty prompt"}
        
        if not self.model:
            return {"error": "Model not loaded"}
        
        try:
            language_hint = (language or "sv").strip().lower()
            if language_hint:
                prompt = f"Språk: {language_hint}\n\n{prompt}"

            generated = self._generate(prompt, max_tokens=max_length)

            return {
                "prompt": prompt,
                "generated_text": generated,
                "truncated": len(generated) >= max_length
            }
        except Exception as e:
            logger.error(f"Text generation failed: {e}")
            return {
                "prompt": prompt,
                "error": str(e)
            }

    def _generate(self, prompt: str, max_tokens: int) -> str:
        """Generate text with llama-cpp and return raw completion."""
        try:
            result = self.model(
                prompt,
                max_tokens=max_tokens,
                temperature=0.7,
                top_p=0.9,
                stop=None,
                echo=False
            )
        except TypeError:
            # Some llama-cpp-python versions don't support `echo`.
            result = self.model(
                prompt,
                max_tokens=max_tokens,
                temperature=0.7,
                top_p=0.9,
                stop=None
            )

        return result["choices"][0]["text"].strip()

    def _strip_prompt_echo(self, generated: str) -> str:
        """
        Remove prompt echo and return only the final answer.

        Preferred extraction: keep text after the last `SVAR:` marker.
        If we still detect that the model echoed the prompt/content, return empty
        so the caller can fall back to placeholder formatting.
        """
        if not generated:
            return ""

        text = generated.strip()

        marker = "SVAR:"
        if marker in text:
            text = text.split(marker)[-1].strip()

        # If the output still contains large chunks of the prompt/content, treat as echo.
        echo_markers = [
            "Du är en språkassistent",
            "VIKTIGT:",
            "BEGIN CONTENT",
            "END CONTENT",
            "[KÄLLA:",
            "UNDERLAG:"
        ]
        if any(m in text for m in echo_markers):
            return ""

        # Defensive: avoid returning the whole input prompt verbatim.
        if text.count("[KÄLLA:") >= 2:
            return ""

        return text

    def _placeholder_formulation(self, items: List[ContentObject], intent: str) -> Dict:
        """
        Placeholder formulation when model is not available.
        Extracts and formats item content without generation.
        """
        try:
            lines = []
            for i, item in enumerate(items, 1):
                source_label = item.source.upper() if hasattr(item.source, 'upper') else str(item.source)
                lines.append(f"{i}. [{source_label}] {item.subject or 'Untitled'}")
                if item.body:
                    lines.append(f"   {item.body[:100]}...")
            
            formulated = "\n".join(lines)
            
            return {
                "formulated": formulated,
                "intent": intent,
                "items_count": len(items),
                "sources": list(set(item.source for item in items)),
                "mode": "placeholder"
            }
        except Exception as e:
            logger.error(f"Placeholder formulation failed: {e}")
            return {
                "error": f"Formulation failed: {e}",
                "intent": intent
            }


# Singleton instance
_text_service: Optional[TextGenerationService] = None


def get_text_generation_service() -> TextGenerationService:
    """Get or create singleton service."""
    global _text_service
    if _text_service is None:
        _text_service = TextGenerationService()
    return _text_service
