from app.utils.session_store import CompletedSessionsStore, InMemorySessionStore


def test_session_store_enforces_owner_and_deletion():
    store = InMemorySessionStore()
    store.save("session-1", "owner-a", {"value": 1})
    assert store.load("session-1", "owner-b") is None
    assert store.load("session-1", "owner-a") == {"value": 1}
    store.delete("session-1", "owner-b")
    assert store.load("session-1", "owner-a") == {"value": 1}
    store.delete("session-1", "owner-a")
    assert store.load("session-1", "owner-a") is None


def test_expired_session_is_removed(monkeypatch):
    ticks = iter((100.0, 100.0, 161.0))
    monkeypatch.setattr("app.utils.session_store.time.monotonic", lambda: next(ticks))
    store = InMemorySessionStore(ttl_seconds=60)
    store.save("session-1", "owner-a", "payload")
    assert store.load("session-1", "owner-a") == "payload"
    assert store.load("session-1", "owner-a") is None
    assert "session-1" not in store._sessions


def test_completed_history_is_deduplicated_and_bounded():
    store = CompletedSessionsStore(max_sessions_per_user=2)
    store.add_completed_session("owner", {"id": "one", "score": 10})
    store.add_completed_session("owner", {"id": "two", "score": 20})
    store.add_completed_session("owner", {"id": "one", "score": 99})
    store.add_completed_session("owner", {"id": "three", "score": 30})
    assert store.get_user_sessions("owner") == [
        {"id": "three", "score": 30},
        {"id": "one", "score": 99},
    ]


def test_completed_history_returns_copy_and_supports_user_erasure():
    store = CompletedSessionsStore()
    store.add_completed_session("owner", {"id": "one", "score": 10})
    result = store.get_user_sessions("owner")
    result[0]["score"] = 0
    assert store.get_user_sessions("owner")[0]["score"] == 10
    store.delete_user("owner")
    assert store.get_user_sessions("owner") == []
