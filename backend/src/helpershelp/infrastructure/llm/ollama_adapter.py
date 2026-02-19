import logging
import os
from typing import Dict, List, Optional
from datetime import datetime

from helpershelp.retrieval.content_object import ContentObject

try:
    import requests
except ImportError:  # pragma: no cover
    requests = None

logger = logging.getLogger(__name__)


class OllamaTextGenerationService:
    """
    Ollama Qwen2.5 7B formulation service.
    
    ONLY formulates and summarizes already-retrieved information.
    Does NOT search, interpret, or make assumptions.
    
    Replaces GPT-SW3 (GGUF / llama-cpp) with Ollama local inference.
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
        """Initialize Ollama client."""
        self.model_available = False
        self.ollama_host = os.getenv("OLLAMA_HOST", "http://localhost:11434")
        self.ollama_model = os.getenv("OLLAMA_MODEL", "qwen2.5:7b")
        
        if requests is None:
            logger.warning("requests library not available - Ollama service will not work")
            return
        
        try:
            logger.info(f"[OllamaTextGenerationService] Connecting to Ollama at {self.ollama_host}")
            logger.info(f"[OllamaTextGenerationService] Using model: {self.ollama_model}")
            
            # Check if Ollama is available
            self._check_health()
            
            logger.info("✅ Ollama connection established")
            self.model_available = True
            
        except Exception as e:
            logger.warning(f"⚠️  Ollama connection failed: {e} - using placeholder mode")
            self.model_available = False

    def _check_health(self) -> bool:
        """
        Check if Ollama is available and responsive.
        
        Returns:
            True if Ollama is available, False otherwise
        """
        try:
            response = requests.get(f"{self.ollama_host}/api/tags", timeout=5)
            if response.status_code == 200:
                # Check if our model is available
                models = response.json().get("models", [])
                model_names = [m.get("name", "") for m in models]
                
                # Check for exact match or partial match (e.g., "qwen2.5:7b" in "qwen2.5:7b-instruct")
                model_found = any(
                    self.ollama_model in name or name.startswith(self.ollama_model.split(":")[0])
                    for name in model_names
                )
                
                if not model_found:
                    logger.warning(
                        f"Model {self.ollama_model} not found. Available models: {', '.join(model_names)}"
                    )
                    logger.warning("Ollama will attempt to pull the model on first use")
                
                return True
            return False
        except Exception as e:
            logger.error(f"Ollama health check failed: {e}")
            return False

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
            logger.warning("Using placeholder formulation mode (Ollama not available)")
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
            generated = self._generate(prompt, max_tokens=500)
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
        Build structured content blocks for Ollama.
        
        Format:
        [KÄLLA: EMAIL]
        Datum: 2024-11-03
        Innehåll:
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
                f"{date_str}Innehåll:\n"
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
        Build input prompt for Ollama.
        
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
Du ska endast använda detta innehåll.
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
        
        if not self.model_available:
            return {"error": "Ollama not available"}
        
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
        """
        Generate text with Ollama and return completion.
        
        Uses the /api/generate endpoint with streaming disabled for simplicity.
        """
        try:
            full_prompt = f"{self.SYSTEM_PROMPT}\n\n{prompt}"
            
            payload = {
                "model": self.ollama_model,
                "prompt": full_prompt,
                "stream": False,
                "options": {
                    "temperature": 0.7,
                    "top_p": 0.9,
                    "num_predict": max_tokens,
                }
            }
            
            response = requests.post(
                f"{self.ollama_host}/api/generate",
                json=payload,
                timeout=60
            )
            
            if response.status_code != 200:
                raise Exception(f"Ollama request failed with status {response.status_code}: {response.text}")
            
            result = response.json()
            return result.get("response", "").strip()
            
        except requests.exceptions.Timeout:
            raise Exception("Ollama request timed out")
        except requests.exceptions.ConnectionError as e:
            raise Exception(f"Could not connect to Ollama at {self.ollama_host}: {e}")
        except Exception as e:
            raise Exception(f"Ollama generation failed: {e}")

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
        Placeholder formulation when Ollama is not available.
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
_ollama_service: Optional[OllamaTextGenerationService] = None


def get_ollama_text_generation_service() -> OllamaTextGenerationService:
    """Get or create singleton service."""
    global _ollama_service
    if _ollama_service is None:
        _ollama_service = OllamaTextGenerationService()
    return _ollama_service
