import os

import jwt
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# Development secret must match the one in test environment or fallback
TEST_SECRET = os.environ.get(
    "SUPABASE_JWT_SECRET", "dev-secret-do-not-use-in-production-replace-with-supabase-jwt-secret"
)

# Helper to generate a valid test token
def _get_test_token(user_id: str = "test-user-123") -> str:
    return jwt.encode({"sub": user_id}, TEST_SECRET, algorithm="HS256")

# Authenticated client helper
class AuthClient:
    def __init__(self, token: str):
        self.headers = {"Authorization": f"Bearer {token}"}

    def post(self, url: str, **kwargs):
        headers = kwargs.pop("headers", {})
        headers.update(self.headers)
        return client.post(url, headers=headers, **kwargs)

auth_client = AuthClient(_get_test_token())

def test_health_ok():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"



def test_full_technical_flow_start_answer_finish():
    start_resp = auth_client.post("/technical/start", json={
        "name": "Test Candidate",
        "target_role": "SWE Intern",
        "experience": "Intermediate",
        "selected_domains": ["Algorithms", "Data Structures"],
        "desired_difficulty": 3,
        "mode": "PRACTICE",
        "max_questions": 3,
    })
    assert start_resp.status_code == 200
    body = start_resp.json()
    session_id = body["session_id"]
    assert body["question"]["domain"] in {"Algorithms", "Data Structures"}

    completed = False
    for _ in range(3):
        answer_resp = auth_client.post("/technical/answer", json={
            "session_id": session_id,
            "answer": "This is correct because sorted input allows halving the search space, giving logarithmic complexity.",
        })
        assert answer_resp.status_code == 200
        payload = answer_resp.json()
        if payload["completed"]:
            completed = True
            break

    assert completed
    finish_resp = auth_client.post(f"/technical/finish/{session_id}")
    assert finish_resp.status_code == 200
    report = finish_resp.json()["report"]
    assert report["questions_answered"] >= 1

    # session should be gone after finish
    assert auth_client.post(f"/technical/finish/{session_id}").status_code == 404


def test_unknown_session_returns_404():
    resp = auth_client.post("/technical/answer", json={"session_id": "does-not-exist", "answer": "x"})
    assert resp.status_code == 404


def test_empty_answer_rejected():
    start_resp = auth_client.post("/technical/start", json={
        "name": "Test", "target_role": "SWE", "experience": "Beginner",
        "selected_domains": ["Algorithms"], "max_questions": 3,
    })
    session_id = start_resp.json()["session_id"]
    resp = auth_client.post("/technical/answer", json={"session_id": session_id, "answer": "   "})
    assert resp.status_code == 422


def test_multiple_start_requests_create_fresh_sessions():
    payload = {
        "name": "Test Candidate",
        "target_role": "SWE Intern",
        "experience": "Intermediate",
        "selected_domains": ["Data Structures"],
        "desired_difficulty": 3,
        "mode": "PRACTICE",
        "max_questions": 3,
    }

    start1 = auth_client.post("/technical/start", json=payload)
    assert start1.status_code == 200
    body1 = start1.json()

    start2 = auth_client.post("/technical/start", json=payload)
    assert start2.status_code == 200
    body2 = start2.json()

    assert body1["session_id"] != body2["session_id"]
    assert body1["question"]["id"] is not None
    assert body2["question"]["id"] is not None

    from app.utils.session_store import technical_sessions
    c1 = technical_sessions.load(body1["session_id"], "test-user-123")
    c2 = technical_sessions.load(body2["session_id"], "test-user-123")
    
    if c1 and c2:
        assert len(c1.state.question_history) == 0
        assert len(c2.state.question_history) == 0
        assert c1.state is not c2.state

