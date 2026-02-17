"""
Tests for Stage 3 location source support.
"""
from datetime import datetime, timedelta
import pytest
from unittest.mock import patch, MagicMock

from helpershelp.assistant.models import UnifiedItem, UnifiedItemType
from helpershelp.domain.value_objects.time_utils import utcnow


class TestLocationIngest:
    """Tests for location item ingestion."""

    def test_ingest_location_item(self, client, mock_store):
        """Location items are ingested with correct source/type mapping."""
        location_item = {
            "id": "location:59.33:18.07:202602131200",
            "source": "locations",
            "type": "location",
            "title": "Nära Stockholm",
            "body": "Nära Stockholm kl 12:00 (noggrannhet: ca 100 m)",
            "created_at": utcnow().isoformat(),
            "updated_at": utcnow().isoformat(),
            "start_at": utcnow().isoformat(),
            "status": {
                "accuracy_m": 100,
                "lat_bucket": 59.33,
                "lon_bucket": 18.07,
                "place_label": "Stockholm",
                "is_approximate": True,
            },
        }

        response = client.post("/ingest", json={"items": [location_item]})
        assert response.status_code == 200

        # Verify store was called with correct item
        assert mock_store.upsert_items.called
        items = mock_store.upsert_items.call_args[0][0]
        assert len(items) == 1
        assert items[0].source == "locations"
        assert items[0].type == UnifiedItemType.location

    def test_ingest_location_triggers_audit_event(self, client, mock_store):
        """Location ingestion triggers stage3_location_ingest audit event."""
        location_item = {
            "id": "location:59.33:18.07:202602131200",
            "source": "locations",
            "type": "location",
            "title": "Nära Stockholm",
            "body": "Test body",
            "created_at": utcnow().isoformat(),
            "updated_at": utcnow().isoformat(),
        }

        mock_store.upsert_items.return_value = (1, 0)
        response = client.post("/ingest", json={"items": [location_item]})
        assert response.status_code == 200

        # Check that audit was called with stage3_location_ingest
        audit_calls = [
            call for call in mock_store.audit.call_args_list
            if call[0][0] == "stage3_location_ingest"
        ]
        assert len(audit_calls) == 1
        assert audit_calls[0][0][1]["count"] == 1


class TestLocationRetention:
    """Tests for 7-day location retention."""

    def test_location_older_than_7_days_filtered(self, client, mock_store):
        """Locations older than 7 days are filtered out in assistant_store_fetch."""
        old_location = MagicMock()
        old_location.id = "location:59.33:18.07:old"
        old_location.source = "locations"
        old_location.type = MagicMock(value="location")
        old_location.title = "Old location"
        old_location.body = "Old body"
        old_location.start_at = utcnow() - timedelta(days=8)
        old_location.created_at = utcnow() - timedelta(days=8)
        old_location.updated_at = utcnow() - timedelta(days=8)
        old_location.status = {}

        new_location = MagicMock()
        new_location.id = "location:59.33:18.07:new"
        new_location.source = "locations"
        new_location.type = MagicMock(value="location")
        new_location.title = "New location"
        new_location.body = "New body"
        new_location.start_at = utcnow() - timedelta(days=1)
        new_location.created_at = utcnow() - timedelta(days=1)
        new_location.updated_at = utcnow() - timedelta(days=1)
        new_location.status = {}

        mock_store.list_items.return_value = [old_location, new_location]

        from helpershelp.api.deps import assistant_store_fetch
        with patch("helpershelp.api.deps.get_assistant_store", return_value=mock_store):
            results = assistant_store_fetch(
                time_range={"days": 30},
                data_filter={"appliesTo": ["locations"]},
            )

        # Only the new location should be returned
        assert len(results) == 1
        assert results[0].source == "locations"

    def test_location_within_7_days_included(self, client, mock_store):
        """Locations within 7 days are included in results."""
        recent_location = MagicMock()
        recent_location.id = "location:59.33:18.07:recent"
        recent_location.source = "locations"
        recent_location.type = MagicMock(value="location")
        recent_location.title = "Recent location"
        recent_location.body = "Recent body"
        recent_location.start_at = utcnow() - timedelta(days=3)
        recent_location.created_at = utcnow() - timedelta(days=3)
        recent_location.updated_at = utcnow() - timedelta(days=3)
        recent_location.status = {}

        mock_store.list_items.return_value = [recent_location]

        from helpershelp.api.deps import assistant_store_fetch
        with patch("helpershelp.api.deps.get_assistant_store", return_value=mock_store):
            results = assistant_store_fetch(
                time_range={"days": 30},
                data_filter={"appliesTo": ["locations"]},
            )

        assert len(results) == 1


class TestLocationQueryEvidence:
    """Tests for location evidence in query responses."""

    def test_query_returns_location_evidence(self, client, mock_store):
        """Query with location data returns locations in evidence."""
        location = MagicMock()
        location.id = "location:59.33:18.07:202602131200"
        location.source = "locations"
        location.type = MagicMock(value="location")
        location.title = "Nära Stockholm"
        location.body = "Nära Stockholm kl 12:00"
        location.start_at = utcnow()
        location.created_at = utcnow()
        location.updated_at = utcnow()
        location.status = {}

        mock_store.list_items.return_value = [location]

        response = client.post(
            "/query",
            json={
                "query": "var är jag nu?",
                "language": "sv",
                "sources": ["assistant_store"],
                "days": 7,
            },
        )

        assert response.status_code == 200
        data = response.json()
        
        # Check that locations is in used_sources
        used_sources = data.get("used_sources", [])
        assert "locations" in used_sources

        # Check evidence items contain location type
        evidence_items = data.get("evidence_items", [])
        location_evidence = [e for e in evidence_items if e.get("type") == "location"]
        assert len(location_evidence) >= 1


class TestLocationSourceMapping:
    """Tests for location source normalization."""

    def test_location_source_normalized(self, mock_store):
        """'location' and 'locations' are normalized to 'locations'."""
        from helpershelp.api.deps import assistant_store_fetch

        item_singular = MagicMock()
        item_singular.id = "loc1"
        item_singular.source = "location"  # singular
        item_singular.type = MagicMock(value="location")
        item_singular.title = "Test"
        item_singular.body = "Body"
        item_singular.start_at = utcnow()
        item_singular.created_at = utcnow()
        item_singular.updated_at = utcnow()
        item_singular.status = {}

        item_plural = MagicMock()
        item_plural.id = "loc2"
        item_plural.source = "locations"  # plural
        item_plural.type = MagicMock(value="location")
        item_plural.title = "Test 2"
        item_plural.body = "Body 2"
        item_plural.start_at = utcnow()
        item_plural.created_at = utcnow()
        item_plural.updated_at = utcnow()
        item_plural.status = {}

        mock_store.list_items.return_value = [item_singular, item_plural]

        with patch("helpershelp.api.deps.get_assistant_store", return_value=mock_store):
            results = assistant_store_fetch(
                time_range={"days": 7},
                data_filter={"appliesTo": ["locations"]},
            )

        # Both should be returned with normalized 'locations' source
        assert len(results) == 2
        assert all(r.source == "locations" for r in results)


# Fixtures

@pytest.fixture
def client():
    """Create test client."""
    from fastapi.testclient import TestClient
    from helpershelp.api.deps import reset_assistant_store
    
    reset_assistant_store()
    
    # Import app after reset
    from api import app
    return TestClient(app)


@pytest.fixture
def mock_store():
    """Create mock assistant store."""
    from unittest.mock import MagicMock
    store = MagicMock()
    store.upsert_items.return_value = (1, 0)
    store.list_items.return_value = []
    store.audit.return_value = None
    store.get_settings.return_value = {}
    store.upsert_settings.return_value = {}
    store.list_audit_events.return_value = []
    
    with patch("helpershelp.api.deps.get_assistant_store", return_value=store):
        yield store
