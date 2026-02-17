import unittest

from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.retrieval.content_object import ContentObject, MailSender
from helpershelp.retrieval.retrieval_coordinator import RetrievalConfig, RetrievalCoordinator


class RetrievalSourceCapsStage2Tests(unittest.TestCase):
    def test_stage2_caps_exist_in_default_config(self):
        config = RetrievalConfig()
        self.assertIn("contacts", config.max_per_source)
        self.assertIn("photos", config.max_per_source)
        self.assertIn("files", config.max_per_source)

    def test_filter_and_select_applies_stage2_source_caps(self):
        config = RetrievalConfig(
            relevance_threshold=0.0,
            max_items_total=20,
            max_per_source={
                "contacts": 2,
                "photos": 2,
                "files": 2,
                "default": 1,
            },
        )
        coordinator = RetrievalCoordinator(config=config)

        def make_item(item_id: str, source: str) -> dict:
            return {
                "item": ContentObject(
                    id=item_id,
                    source=source,
                    subject=f"{source}-{item_id}",
                    body="stage2 token",
                    sender=MailSender(address="noreply@example.com", name=None, domain="example.com"),
                    received_at=utcnow(),
                    thread_id=None,
                    is_replied=False,
                ),
                "score": 0.99,
            }

        scored_items = [
            make_item("c1", "contacts"),
            make_item("c2", "contacts"),
            make_item("c3", "contacts"),
            make_item("p1", "photos"),
            make_item("p2", "photos"),
            make_item("p3", "photos"),
            make_item("f1", "files"),
            make_item("f2", "files"),
            make_item("f3", "files"),
        ]

        selected = coordinator._filter_and_select(scored_items)
        counts = {}
        for item in selected:
            counts[item.source] = counts.get(item.source, 0) + 1

        self.assertLessEqual(counts.get("contacts", 0), 2)
        self.assertLessEqual(counts.get("photos", 0), 2)
        self.assertLessEqual(counts.get("files", 0), 2)
        self.assertEqual(counts.get("contacts", 0), 2)
        self.assertEqual(counts.get("photos", 0), 2)
        self.assertEqual(counts.get("files", 0), 2)


if __name__ == "__main__":
    unittest.main()
