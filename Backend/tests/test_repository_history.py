import asyncio

import httpx

from app.repository import SupabaseRepository


def test_feedback_for_sessions_batches_history_scores():
    requests = []

    def handle(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        raw_ids = request.url.params["session_id"].removeprefix("in.(").removesuffix(")")
        ids = raw_ids.split(",")
        assert len(ids) <= 40
        return httpx.Response(200, json=[{"session_id": sid, "overall_score": 75} for sid in ids])

    repo = SupabaseRepository(
        url="https://example.supabase.co",
        anon_key="test-key",
        transport=httpx.MockTransport(handle),
    )
    ids = [f"session-{i}" for i in range(81)]
    scores = asyncio.run(repo.feedback_for_sessions(ids, "test-token"))

    assert len(requests) == 3
    assert len(scores) == 81
    assert scores["session-80"]["overall_score"] == 75
    assert asyncio.run(repo.feedback_for_sessions([], "test-token")) == {}
    assert len(requests) == 3


def test_session_history_excludes_unfinished_interviews():
    def handle(request: httpx.Request) -> httpx.Response:
        assert request.url.params["status"] == "eq.completed"
        assert request.url.params["user_id"] == "eq.user-1"
        return httpx.Response(200, json=[])

    repo = SupabaseRepository(
        url="https://example.supabase.co",
        anon_key="test-key",
        transport=httpx.MockTransport(handle),
    )
    assert asyncio.run(repo.sessions("user-1", "test-token")) == []
