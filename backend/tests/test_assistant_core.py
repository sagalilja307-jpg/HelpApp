import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

from helpershelp.assistant.models import ExternalRef, Person, UnifiedItem, UnifiedItemType
from helpershelp.application.assistant.proposals import generate_proposals
from helpershelp.domain.rules.scoring import score_item
from helpershelp.assistant.storage import SqliteStore, StoreConfig
from helpershelp.domain.value_objects.time_utils import utcnow


class AssistantCoreTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test.db"
        self.store = SqliteStore(StoreConfig(db_path=self.db_path))
        self.store.init()

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_upsert_by_external_ref(self):
        now = utcnow()
        item1 = UnifiedItem(
            source="gmail",
            type=UnifiedItemType.email,
            title="Hello",
            body="First",
            created_at=now - timedelta(days=1),
            updated_at=now - timedelta(days=1),
            external_ref=ExternalRef(provider="gmail", provider_id="msg1", url=None),
            status={"email": {"direction": "inbound", "thread_id": "t1", "is_replied": False}},
            people=[Person(address="a@example.com")],
        )
        ins, upd = self.store.upsert_items([item1])
        self.assertEqual(ins, 1)
        self.assertEqual(upd, 0)

        if hasattr(item1, "model_copy"):
            item2 = item1.model_copy(update={"body": "Second", "updated_at": now})  # pydantic v2
        else:
            item2 = item1.copy(update={"body": "Second", "updated_at": now})  # pydantic v1
        ins2, upd2 = self.store.upsert_items([item2])
        self.assertEqual(ins2, 0)
        self.assertEqual(upd2, 1)

        items = self.store.list_items(limit=10)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].body, "Second")

    def test_scoring_email_unreplied_old(self):
        now = utcnow()
        item = UnifiedItem(
            source="gmail",
            type=UnifiedItemType.email,
            title="Question?",
            body="Please respond",
            created_at=now - timedelta(days=5),
            updated_at=now - timedelta(days=5),
            status={"email": {"direction": "inbound", "is_replied": False, "thread_id": "t1"}},
        )
        s = score_item(item, now)
        self.assertGreaterEqual(s.score, 0.6)

    def test_generate_followup_proposal(self):
        now = utcnow()
        item = UnifiedItem(
            source="gmail",
            type=UnifiedItemType.email,
            title="Need your answer?",
            body="Can you confirm?",
            created_at=now - timedelta(days=4),
            updated_at=now - timedelta(days=4),
            status={"email": {"direction": "inbound", "is_replied": False, "thread_id": "t1"}},
        )
        props = generate_proposals([item], now=now, settings={"assistant.follow_up_days": 3})
        self.assertTrue(any(p.proposal_type.value == "follow_up" for p in props))

    def test_generate_create_reminder_proposal(self):
        now = utcnow()
        item = UnifiedItem(
            source="gmail",
            type=UnifiedItemType.email,
            title="Please send by Friday",
            body="Thanks",
            created_at=now - timedelta(days=1),
            updated_at=now - timedelta(days=1),
            status={"email": {"direction": "inbound", "is_replied": None, "thread_id": "t1"}},
        )
        props = generate_proposals([item], now=now, settings={})
        self.assertTrue(any(p.proposal_type.value == "create_reminder" for p in props))

    def test_schedule_timeblock_proposal(self):
        now = utcnow()
        task = UnifiedItem(
            source="ios_push",
            type=UnifiedItemType.task,
            title="Write report",
            body="",
            created_at=now,
            updated_at=now,
            due_at=now + timedelta(days=2),
            status={"state": "open"},
        )
        # Busy event tomorrow 9-11, so expect alternative slot
        ev = UnifiedItem(
            source="gcal",
            type=UnifiedItemType.event,
            title="Meeting",
            body="",
            created_at=now,
            updated_at=now,
            start_at=(now + timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0),
            end_at=(now + timedelta(days=1)).replace(hour=11, minute=0, second=0, microsecond=0),
        )
        props = generate_proposals([task, ev], now=now, settings={"assistant.schedule_duration_minutes": 120})
        sched = [p for p in props if p.proposal_type.value == "schedule_timeblock"]
        self.assertEqual(len(sched), 1)
        slots = sched[0].actions.get("recommended_slots") or []
        self.assertGreaterEqual(len(slots), 1)


if __name__ == "__main__":
    unittest.main()
