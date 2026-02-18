"""
Shim import smoke tests.

These tests verify that legacy import paths still resolve.
Deprecation warnings are optional and not enforced by this suite.
"""


def test_assistant_scoring_shim_imports():
    from helpershelp.domain.rules.scoring import score_item

    assert callable(score_item)


def test_assistant_support_shim_imports():
    from helpershelp.application.assistant import support as support_module

    assert support_module is not None


def test_assistant_sync_shim_imports():
    from helpershelp.assistant import sync as sync_module

    assert sync_module is not None


def test_assistant_crypto_shim_imports():
    from helpershelp.infrastructure.security.crypto_utils import get_fernet

    assert callable(get_fernet)


def test_assistant_storage_shim_imports():
    from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore

    assert SqliteStore is not None


def test_assistant_time_utils_shim_imports():
    from helpershelp.domain.value_objects.time_utils import utcnow

    assert callable(utcnow)


def test_assistant_tokens_shim_imports():
    from helpershelp.infrastructure.security.token_manager import store_oauth_token

    assert callable(store_oauth_token)


def test_assistant_proposals_shim_imports():
    from helpershelp.application.assistant.proposals import generate_proposals

    assert callable(generate_proposals)


def test_assistant_scheduling_shim_imports():
    from helpershelp.domain.rules.scheduling import TimeSlot

    assert TimeSlot is not None


def test_mail_oauth_service_shim_imports():
    from helpershelp.mail.oauth_service import OAuthService

    assert OAuthService is not None


def test_mail_mail_query_service_shim_imports():
    from helpershelp.mail.mail_query_service import MailQueryService

    assert MailQueryService is not None
