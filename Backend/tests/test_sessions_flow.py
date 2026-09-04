from __future__ import annotations
import pytest
from fastapi.testclient import TestClient

def test_sessions_and_detail_flow(client: TestClient, auth_headers: dict[str, str], second_auth_headers: dict[str, str]):
    # 1. Initially sessions should be empty for User A
    resp = client.get("/sessions", headers=auth_headers)
    assert resp.status_code == 200
    assert resp.json() == []

    # 2. Start a technical session for User A
    start_resp = client.post(
        "/technical/start",
        json={
            "name": "Test Candidate",
            "target_role": "Backend Engineer",
            "experience": "Intermediate",
            "selected_domains": ["Data Structures"],
            "desired_difficulty": 3
        },
        headers=auth_headers
    )

    assert start_resp.status_code == 200
    session_id = start_resp.json()["session_id"]

    # Answer question
    ans_resp = client.post(
        "/technical/answer",
        json={"session_id": session_id, "answer": "Hash maps use hashing for O(1) average access time."},
        headers=auth_headers
    )
    assert ans_resp.status_code == 200

    # Finish session
    finish_resp = client.post(
        f"/technical/finish/{session_id}",
        headers=auth_headers
    )
    assert finish_resp.status_code == 200

    # 3. Check /sessions now lists 1 session for User A
    sessions_resp = client.get("/sessions", headers=auth_headers)
    assert sessions_resp.status_code == 200
    items = sessions_resp.json()
    assert len(items) == 1
    assert items[0]["id"] == session_id
    assert items[0]["kind"] == "technical"

    # 4. Check /sessions/{session_id} returns detailed report and transcript for User A
    detail_resp = client.get(f"/sessions/{session_id}", headers=auth_headers)
    assert detail_resp.status_code == 200
    detail = detail_resp.json()
    assert detail["id"] == session_id
    assert detail["kind"] == "technical"
    assert "report" in detail
    assert "transcript" in detail

    # 5. Account Isolation: User B attempts to get User A's session detail -> HTTP 404
    user_b_resp = client.get(f"/sessions/{session_id}", headers=second_auth_headers)
    assert user_b_resp.status_code == 404

    # 6. Non-existent session -> HTTP 404
    non_existent = client.get("/sessions/invalid-session-id-999", headers=auth_headers)
    assert non_existent.status_code == 404


def test_gd_sessions_and_detail_flow(client: TestClient, auth_headers: dict[str, str], second_auth_headers: dict[str, str], monkeypatch):
    # Mock LLM router for GD to run deterministically without calling external API
    from app.config import get_settings
    from app.providers.model_router import ModelRouter
    from app.providers.llm_backend import LLMBackend, GenerationRequest, GenerationResult
    class DummyBackend(LLMBackend):
        def generate(self, request: GenerationRequest) -> GenerationResult:
            return GenerationResult(
                text="I believe remote work increases productivity when communication tools are effectively utilized.",
                provider="mock",
                model="mock",
                input_tokens=10,
                output_tokens=10,
                latency_seconds=0.1,
                retry_count=0
            )
    
    router = ModelRouter(get_settings(), DummyBackend())
    monkeypatch.setattr("app.routers.gd._backend_router", lambda settings: router)



    # 1. Start GD session for User A
    start_resp = client.post(
        "/gd/start",
        json={"topic": "Remote work and productivity", "num_rounds": 2, "mode": "balanced"},
        headers=auth_headers
    )
    assert start_resp.status_code == 200
    session_id = start_resp.json()["session_id"]
    assert session_id is not None

    # 2. Submit user contribution
    respond_resp = client.post(
        "/gd/respond",
        json={"session_id": session_id, "user_contribution": "Flexible hours help maintain work-life balance."},
        headers=auth_headers
    )
    assert respond_resp.status_code == 200

    # 3. Finish GD session
    finish_resp = client.post(
        f"/gd/finish/{session_id}",
        headers=auth_headers
    )
    assert finish_resp.status_code == 200
    fin_data = finish_resp.json()
    assert "metrics" in fin_data
    assert "summary" in fin_data

    # 4. Verify GET /sessions for User A contains completed GD session
    sessions_resp = client.get("/sessions", headers=auth_headers)
    assert sessions_resp.status_code == 200
    items = sessions_resp.json()
    assert len(items) == 1
    assert items[0]["id"] == session_id
    assert items[0]["kind"] == "gd"

    # 5. Verify GET /sessions/{session_id} returns detail, report, and transcript
    detail_resp = client.get(f"/sessions/{session_id}", headers=auth_headers)
    assert detail_resp.status_code == 200
    detail = detail_resp.json()
    assert detail["id"] == session_id
    assert detail["kind"] == "gd"
    assert "report" in detail
    assert "transcript" in detail
    
    report = detail["report"]
    assert "metrics" in report
    assert "summary" in report
    assert "strengths" in report
    assert "weaknesses" in report
    assert "missing_concepts" in report
    assert "recommendations" in report

    # 6. Verify User B cannot access User A's GD session (404)
    user_b_resp = client.get(f"/sessions/{session_id}", headers=second_auth_headers)
    assert user_b_resp.status_code == 404

    # 7. Verify invalid GD session ID returns 404
    non_existent = client.get("/sessions/invalid-gd-session-999", headers=auth_headers)
    assert non_existent.status_code == 404
