import unittest
from tests.api_test_case import APIRouteTestCase


class QueryStage3LocationTests(APIRouteTestCase):
    db_filename = "test_stage3_locations.db"

    def test_location_query_returns_location_domain(self):
        response = self.client.post(
            "/query",
            json={"query": "Var är jag nu?", "language": "sv"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json().get("data_intent") or {}
        self.assertEqual(payload.get("domain"), "location")
        self.assertEqual(payload.get("operation"), "list")


if __name__ == "__main__":
    unittest.main()
