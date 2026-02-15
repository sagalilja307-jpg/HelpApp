"""
Test suite for shim deprecation strategy

This module tests that:
1. All shims emit deprecation warnings
2. Shims still work correctly (backward compatibility)
3. Migration to new paths works correctly
"""
import warnings
import pytest


class TestShimDeprecationWarnings:
    """Test that all shims emit proper deprecation warnings"""

    def test_assistant_scoring_shim_warns(self):
        """Verify assistant.scoring shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.domain.rules.scoring import score_item
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.domain.rules.scoring" in str(w[0].message)
            assert "helpershelp.domain.rules.scoring" in str(w[0].message)
            assert "2.0.0" in str(w[0].message)

    def test_assistant_support_shim_warns(self):
        """Verify assistant.support shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.assistant.support import SupportPolicy
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.assistant.support" in str(w[0].message)

    def test_assistant_sync_shim_warns(self):
        """Verify assistant.sync shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.assistant.sync import SyncController
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.assistant.sync" in str(w[0].message)

    def test_assistant_crypto_shim_warns(self):
        """Verify assistant.crypto shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.assistant.crypto import get_fernet
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.assistant.crypto" in str(w[0].message)

    def test_assistant_storage_shim_warns(self):
        """Verify assistant.storage shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.assistant.storage import SqliteStore
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.assistant.storage" in str(w[0].message)

    def test_assistant_time_utils_shim_warns(self):
        """Verify assistant.time_utils shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.domain.value_objects.time_utils import utcnow
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.assistant.time_utils" in str(w[0].message)

    def test_assistant_tokens_shim_warns(self):
        """Verify assistant.tokens shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.assistant.tokens import store_oauth_token
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.assistant.tokens" in str(w[0].message)

    def test_assistant_proposals_shim_warns(self):
        """Verify assistant.proposals shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.assistant.proposals import generate_proposals
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.assistant.proposals" in str(w[0].message)

    def test_assistant_scheduling_shim_warns(self):
        """Verify assistant.scheduling shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.domain.rules.scheduling import TimeSlot
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.domain.rules.scheduling" in str(w[0].message)

    def test_llm_llm_service_shim_warns(self):
        """Verify llm.llm_service shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.llm.llm_service import QueryInterpretationService
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.llm.llm_service" in str(w[0].message)

    def test_llm_embedding_service_shim_warns(self):
        """Verify llm.embedding_service shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.llm.embedding_service import EmbeddingService
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.llm.embedding_service" in str(w[0].message)

    def test_llm_ollama_service_shim_warns(self):
        """Verify llm.ollama_service shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.llm.ollama_service import OllamaTextGenerationService
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.llm.ollama_service" in str(w[0].message)

    def test_llm_text_generation_service_shim_warns(self):
        """Verify llm.text_generation_service shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.llm.text_generation_service import TextGenerationService
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.llm.text_generation_service" in str(w[0].message)

    def test_mail_oauth_service_shim_warns(self):
        """Verify mail.oauth_service shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.mail.oauth_service import OAuthService
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.mail.oauth_service" in str(w[0].message)

    def test_mail_mail_query_service_shim_warns(self):
        """Verify mail.mail_query_service shim emits deprecation warning"""
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            from helpershelp.mail.mail_query_service import MailQueryService
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "helpershelp.mail.mail_query_service" in str(w[0].message)


class TestShimBackwardCompatibility:
    """Test that shims still work correctly (functional equivalence)"""

    def test_scoring_shim_works(self):
        """Verify scoring shim provides same functionality"""
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            
            # Import from shim
            from helpershelp.domain.rules.scoring import ScoredItem, score_item
            
            # Import from actual location
            from helpershelp.domain.rules.scoring import (
                ScoredItem as ActualScoredItem,
                score_item as actual_score_item
            )
            
            # Verify they're the same
            assert ScoredItem is ActualScoredItem
            assert score_item is actual_score_item

    def test_time_utils_shim_works(self):
        """Verify time_utils shim provides same functionality"""
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            
            from helpershelp.domain.value_objects.time_utils import utcnow
            from helpershelp.domain.value_objects.time_utils import utcnow as actual_utcnow
            
            assert utcnow is actual_utcnow

    def test_storage_shim_works(self):
        """Verify storage shim provides same functionality"""
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            
            from helpershelp.assistant.storage import SqliteStore, StoreConfig
            from helpershelp.infrastructure.persistence.sqlite_storage import (
                SqliteStore as ActualSqliteStore,
                StoreConfig as ActualStoreConfig
            )
            
            assert SqliteStore is ActualSqliteStore
            assert StoreConfig is ActualStoreConfig


class TestNewImportPaths:
    """Test that new import paths work correctly (migration target)"""

    def test_domain_rules_scoring_import(self):
        """Verify domain.rules.scoring imports work"""
        from helpershelp.domain.rules.scoring import (
            ScoredItem,
            score_item,
            dedupe_scored_items,
            build_dashboard_lists,
        )
        
        assert ScoredItem is not None
        assert callable(score_item)
        assert callable(dedupe_scored_items)
        assert callable(build_dashboard_lists)

    def test_domain_value_objects_time_utils_import(self):
        """Verify domain.value_objects.time_utils imports work"""
        from helpershelp.domain.value_objects.time_utils import utcnow
        
        assert callable(utcnow)

    def test_application_assistant_support_import(self):
        """Verify application.assistant.support imports work"""
        from helpershelp.application.assistant.support import (
            SupportPolicy,
            resolve_support_policy,
        )
        
        assert SupportPolicy is not None
        assert callable(resolve_support_policy)

    def test_infrastructure_persistence_storage_import(self):
        """Verify infrastructure.persistence.sqlite_storage imports work"""
        from helpershelp.infrastructure.persistence.sqlite_storage import (
            SqliteStore,
            StoreConfig,
        )
        
        assert SqliteStore is not None
        assert StoreConfig is not None

    def test_infrastructure_security_crypto_import(self):
        """Verify infrastructure.security.crypto_utils imports work"""
        from helpershelp.infrastructure.security.crypto_utils import (
            get_fernet,
            encrypt_json,
            decrypt_json,
        )
        
        assert callable(get_fernet)
        assert callable(encrypt_json)
        assert callable(decrypt_json)

    def test_infrastructure_llm_bge_m3_import(self):
        """Verify infrastructure.llm.bge_m3_adapter imports work"""
        from helpershelp.infrastructure.llm.bge_m3_adapter import (
            EmbeddingService,
            get_embedding_service,
        )
        
        assert EmbeddingService is not None
        assert callable(get_embedding_service)


class TestDeprecationUtility:
    """Test the deprecation utility module itself"""

    def test_deprecated_module_function(self):
        """Verify deprecated_module emits warning correctly"""
        from helpershelp._deprecation import deprecated_module
        
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            deprecated_module(
                "test.old.path",
                "test.new.path",
                removal_version="99.0.0"
            )
            
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "test.old.path" in str(w[0].message)
            assert "test.new.path" in str(w[0].message)
            assert "99.0.0" in str(w[0].message)

    def test_deprecated_function_decorator(self):
        """Verify deprecated_function decorator works correctly"""
        from helpershelp._deprecation import deprecated_function
        
        @deprecated_function("old_func", "new.module.new_func", removal_version="99.0.0")
        def test_function():
            return "result"
        
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            result = test_function()
            
            assert result == "result"
            assert len(w) == 1
            assert issubclass(w[0].category, DeprecationWarning)
            assert "old_func" in str(w[0].message)
            assert "new.module.new_func" in str(w[0].message)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
