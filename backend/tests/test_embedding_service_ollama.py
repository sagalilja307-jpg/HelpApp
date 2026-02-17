import math
import unittest
from unittest.mock import patch

from helpershelp.infrastructure.llm.bge_m3_adapter import (
    EMBEDDING_BACKEND_UNAVAILABLE,
    EmbeddingService,
)


def _vector_1024(seed: float) -> list[float]:
    vec = [0.0] * 1024
    vec[0] = seed
    vec[1] = 1.0 - seed
    norm = math.sqrt(sum(v * v for v in vec))
    return [v / norm for v in vec]


class _MockResponse:
    def __init__(self, payload, status_code=200):
        self._payload = payload
        self.status_code = status_code
        self.text = str(payload)

    def json(self):
        return self._payload


class EmbeddingServiceOllamaTests(unittest.TestCase):
    def _tags_response(self):
        return _MockResponse(
            {"models": [{"name": "bge-m3"}, {"name": "qwen2.5:7b"}]},
            status_code=200,
        )

    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.post")
    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.get")
    def test_embed_text_returns_dimension_1024(self, mocked_get, mocked_post):
        mocked_get.return_value = self._tags_response()
        mocked_post.return_value = _MockResponse({"embeddings": [_vector_1024(0.6)]}, status_code=200)

        service = EmbeddingService()
        result = service.embed_text("Detta är ett test")

        self.assertNotIn("error", result)
        self.assertEqual(result.get("embedding_dim"), 1024)
        self.assertEqual(len(result.get("embedding", [])), 1024)

    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.post")
    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.get")
    def test_embed_batch_returns_count_and_dimension(self, mocked_get, mocked_post):
        mocked_get.return_value = self._tags_response()
        mocked_post.return_value = _MockResponse(
            {"embeddings": [_vector_1024(0.7), _vector_1024(0.3)]},
            status_code=200,
        )

        service = EmbeddingService()
        result = service.embed_batch(["första", "andra"])

        self.assertNotIn("error", result)
        self.assertEqual(result.get("count"), 2)
        self.assertEqual(result.get("embedding_dim"), 1024)
        self.assertEqual(len(result.get("embeddings", [])), 2)

    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.post")
    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.get")
    def test_fallback_from_api_embed_to_api_embeddings(self, mocked_get, mocked_post):
        mocked_get.return_value = self._tags_response()

        def post_side_effect(url, json, timeout):  # noqa: A002
            if url.endswith("/api/embed"):
                return _MockResponse({"error": "not found"}, status_code=404)
            if url.endswith("/api/embeddings"):
                text = json.get("prompt", "")
                value = 0.8 if text == "a" else 0.2
                return _MockResponse({"embedding": _vector_1024(value)}, status_code=200)
            return _MockResponse({}, status_code=500)

        mocked_post.side_effect = post_side_effect

        service = EmbeddingService()
        result = service.embed_batch(["a", "b"])

        self.assertNotIn("error", result)
        self.assertEqual(result.get("count"), 2)
        self.assertEqual(service.active_embed_endpoint, "/api/embeddings")

    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.get")
    def test_backend_unavailable_maps_to_standard_error_code(self, mocked_get):
        mocked_get.side_effect = RuntimeError("connection refused")

        service = EmbeddingService()
        result = service.embed_text("hej")

        self.assertIn("error", result)
        self.assertEqual(result.get("error_code"), EMBEDDING_BACKEND_UNAVAILABLE)

    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.post")
    @patch("helpershelp.infrastructure.llm.bge_m3_adapter.requests.get")
    def test_embedding_regression_properties_and_ranking(self, mocked_get, mocked_post):
        mocked_get.return_value = self._tags_response()

        query = _vector_1024(1.0)
        near = _vector_1024(0.95)
        mid = _vector_1024(0.55)
        far = _vector_1024(0.05)

        def post_side_effect(url, json, timeout):  # noqa: A002
            if url.endswith("/api/embed"):
                inputs = json.get("input")
                if isinstance(inputs, list):
                    mapping = {
                        "query": query,
                        "near": near,
                        "mid": mid,
                        "far": far,
                    }
                    return _MockResponse(
                        {"embeddings": [mapping[text] for text in inputs]},
                        status_code=200,
                    )
                return _MockResponse({"embeddings": [query]}, status_code=200)
            return _MockResponse({}, status_code=500)

        mocked_post.side_effect = post_side_effect

        service = EmbeddingService()

        single = service.embed_text("query")
        self.assertEqual(single.get("embedding_dim"), 1024)
        norm = math.sqrt(sum(value * value for value in single["embedding"]))
        self.assertGreater(norm, 0.0)

        self_similarity = service.similarity("query", "query")
        self.assertNotIn("error", self_similarity)
        self.assertGreaterEqual(self_similarity.get("similarity", 0.0), 0.999)

        ranked = service.similarity_batch("query", ["far", "mid", "near"])
        self.assertNotIn("error", ranked)
        ordered = [row["text"] for row in ranked.get("ranked", [])]
        self.assertEqual(ordered[:3], ["near", "mid", "far"])


if __name__ == "__main__":
    unittest.main()
