"""Shim removal verification tests.

This suite verifies two things:
1. Historical shim paths are gone.
2. Canonical replacement imports still work.
"""

from __future__ import annotations

import importlib
import warnings

import pytest


REMOVED_SHIM_MODULES = [
    "helpershelp.assistant.sync",
    "helpershelp.llm.embedding_service",
    "helpershelp.llm.llm_service",
    "helpershelp.llm.ollama_service",
    "helpershelp.llm.text_generation_service",
    "helpershelp.mail.oauth_service",
    "helpershelp.mail.mail_query_service",
]

CANONICAL_MODULES = [
    "helpershelp.application.assistant.sync",
    "helpershelp.infrastructure.llm.bge_m3_adapter",
    "helpershelp.application.llm.llm_service",
    "helpershelp.infrastructure.llm.ollama_adapter",
    "helpershelp.application.llm.text_generation_service",
    "helpershelp.infrastructure.security.oauth_adapter",
    "helpershelp.application.mail.mail_query_service",
    "helpershelp.application.assistant.support",
]


class TestRemovedShimImports:
    @pytest.mark.parametrize("module_name", REMOVED_SHIM_MODULES)
    def test_removed_shim_import_fails(self, module_name: str):
        with pytest.raises(ModuleNotFoundError):
            importlib.import_module(module_name)


class TestCanonicalImports:
    @pytest.mark.parametrize("module_name", CANONICAL_MODULES)
    def test_canonical_import_works(self, module_name: str):
        module = importlib.import_module(module_name)
        assert module is not None


class TestDeprecationUtility:
    def test_deprecated_module_function(self):
        from helpershelp._deprecation import deprecated_module

        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            deprecated_module(
                "test.old.path",
                "test.new.path",
                removal_version="99.0.0",
            )
            assert len(caught) == 1
            assert issubclass(caught[0].category, DeprecationWarning)
            assert "test.old.path" in str(caught[0].message)
            assert "test.new.path" in str(caught[0].message)
            assert "99.0.0" in str(caught[0].message)

    def test_deprecated_function_decorator(self):
        from helpershelp._deprecation import deprecated_function

        @deprecated_function("old_func", "new.module.new_func", removal_version="99.0.0")
        def test_function():
            return "result"

        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            result = test_function()
            assert result == "result"
            assert len(caught) == 1
            assert issubclass(caught[0].category, DeprecationWarning)
            assert "old_func" in str(caught[0].message)
            assert "new.module.new_func" in str(caught[0].message)
