from __future__ import annotations

import uuid

import pytest

from app.config import get_settings
from app.main import app
from app.utils.session_store import aptitude_sessions, company_sessions


class ActiveSessionRepository:
    def __init__(self):
        self.sessions: dict[str, dict] = {}
        self.feedback: dict[str, dict] = {}

    async def ensure_profile(self, user_id: str, token: str) -> dict:
        return {"id": user_id}

    async def create_session(self, data: dict, token: str) -> dict:
        session_id = data.get("id") or str(uuid.uuid4())
        row = {"id": session_id, "status": "active", **data}
        self.sessions[session_id] = row
        return row

    async def session(self, session_id: str, user_id: str, token: str) -> dict:
        row = self.sessions.get(session_id)
        if row is None or row.get("user_id") != user_id:
            raise ValueError("not found")
        return row

    async def update_session(self, session_id: str, user_id: str, token: str, data: dict) -> dict:
        row = await self.session(session_id, user_id, token)
        row.update(data)
        return row

    async def upsert_feedback(self, data: dict, token: str) -> dict:
        self.feedback[data["session_id"]] = data
        return data


@pytest.fixture
def active_session_repository(monkeypatch):
    base = get_settings()
    app.dependency_overrides[get_settings] = lambda: base.model_copy(update={
        "use_supabase_persistence": True,
        "use_gemini": False,
    })
    repository = ActiveSessionRepository()
    monkeypatch.setattr("app.routers.aptitude.SupabaseRepository", lambda: repository)
    monkeypatch.setattr("app.routers.company.SupabaseRepository", lambda: repository)
    yield repository
    app.dependency_overrides.pop(get_settings, None)


def test_aptitude_active_session_recovers_after_process_cache_loss(
    client, auth_headers, active_session_repository
):
    started = client.post("/aptitude/start", headers=auth_headers, json={
        "categories": ["Quantitative Aptitude"],
        "question_count": 5,
        "duration_minutes": 10,
    })
    assert started.status_code == 200
    session_id = started.json()["session_id"]
    first_question = started.json()["question"]

    first_answer = client.post("/aptitude/answer", headers=auth_headers, json={
        "session_id": session_id,
        "question_id": first_question["id"],
        "selected_index": 0,
    })
    assert first_answer.status_code == 200
    next_question = first_answer.json()["next_question"]
    assert next_question is not None

    aptitude_sessions.clear()  # Simulate a Render restart or worker replacement.
    resumed = client.post("/aptitude/answer", headers=auth_headers, json={
        "session_id": session_id,
        "question_id": next_question["id"],
        "selected_index": 1,
    })
    assert resumed.status_code == 200
    assert resumed.json()["attempted"] == 2

    aptitude_sessions.clear()
    finished = client.post(f"/aptitude/finish/{session_id}", headers=auth_headers)
    assert finished.status_code == 200
    assert active_session_repository.sessions[session_id]["status"] == "completed"
    assert active_session_repository.sessions[session_id]["topic"].startswith("mockexa:aptitude:v1:")
    aptitude_sessions.clear()
    retried_finish = client.post(f"/aptitude/finish/{session_id}", headers=auth_headers)
    assert retried_finish.status_code == 200
    assert retried_finish.json() == finished.json()


def test_company_active_session_recovers_after_process_cache_loss(
    client, auth_headers, active_session_repository
):
    started = client.post("/company/start", headers=auth_headers, json={
        "company_id": "amazon",
        "question_count": 2,
        "evaluation_mode": "fast",
    })
    assert started.status_code == 200
    session_id = started.json()["session_id"]

    first_answer = client.post("/company/answer", headers=auth_headers, json={
        "session_id": session_id,
        "question_id": started.json()["question"]["id"],
        "answer": "I would clarify requirements, choose a measurable approach, test edge cases, and explain the tradeoffs.",
    })
    assert first_answer.status_code == 200
    next_question = first_answer.json()["next_question"]
    assert next_question is not None

    company_sessions.clear()  # Simulate a Render restart or worker replacement.
    resumed = client.post("/company/answer", headers=auth_headers, json={
        "session_id": session_id,
        "question_id": next_question["id"],
        "answer": "I would define the invariant, measure latency and correctness, then compare alternatives and failure modes.",
    })
    assert resumed.status_code == 200
    assert resumed.json()["completed"] is True

    company_sessions.clear()
    finished = client.post(f"/company/finish/{session_id}", headers=auth_headers)
    assert finished.status_code == 200
    assert finished.json()["questions_answered"] == 2
    assert active_session_repository.sessions[session_id]["status"] == "completed"
    assert active_session_repository.sessions[session_id]["topic"].startswith("mockexa:company:v1:")
    company_sessions.clear()
    retried_finish = client.post(f"/company/finish/{session_id}", headers=auth_headers)
    assert retried_finish.status_code == 200
    assert retried_finish.json() == finished.json()
