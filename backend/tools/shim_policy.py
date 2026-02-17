"""Central shim policy used by local tooling and CI checks.

This list documents historical shim modules that were removed from the codebase.
Any new import to these paths should fail CI.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ShimModule:
    old_path: str
    canonical_path: str


SHIM_MODULES: tuple[ShimModule, ...] = (
    ShimModule("helpershelp.assistant.sync", "helpershelp.application.assistant.sync"),
    ShimModule("helpershelp.llm.embedding_service", "helpershelp.infrastructure.llm.bge_m3_adapter"),
    ShimModule("helpershelp.llm.llm_service", "helpershelp.application.llm.llm_service"),
    ShimModule("helpershelp.llm.ollama_service", "helpershelp.infrastructure.llm.ollama_adapter"),
    ShimModule("helpershelp.llm.text_generation_service", "helpershelp.application.llm.text_generation_service"),
    ShimModule("helpershelp.mail.oauth_service", "helpershelp.infrastructure.security.oauth_adapter"),
    ShimModule("helpershelp.mail.mail_query_service", "helpershelp.application.mail.mail_query_service"),
)

SHIM_MAP: dict[str, str] = {shim.old_path: shim.canonical_path for shim in SHIM_MODULES}
SHIM_OLD_PATHS: tuple[str, ...] = tuple(SHIM_MAP.keys())


def is_shim_module(module_name: str) -> bool:
    """Return True when module_name points at a known shim module path."""
    return any(
        module_name == old_path or module_name.startswith(f"{old_path}.")
        for old_path in SHIM_OLD_PATHS
    )


def canonical_for(module_name: str) -> str | None:
    """Return canonical replacement path for a shim import (if any)."""
    for old_path, canonical_path in SHIM_MAP.items():
        if module_name == old_path:
            return canonical_path
        if module_name.startswith(f"{old_path}."):
            suffix = module_name[len(old_path) :]
            return f"{canonical_path}{suffix}"
    return None
