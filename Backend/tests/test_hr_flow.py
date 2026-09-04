import os
import jwt
import pytest
from unittest.mock import patch
from fastapi.testclient import TestClient

from app.main import app
from app.controllers.hr_controller import HREvaluation, HRQuestion

client = TestClient(app)

TEST_SECRET = os.environ.get(
    "SUPABASE_JWT_SECRET", "dev-secret-do-not-use-in-production-replace-with-supabase-jwt-secret"
)

def _get_test_token(user_id: str = "test-user-123") -> str:
    return jwt.encode({"sub": user_id}, TEST_SECRET, algorithm="HS256")

class AuthClient:
    def __init__(self, token: str):
        self.headers = {"Authorization": f"Bearer {token}"}

    def post(self, url: str, **kwargs):
        headers = kwargs.pop("headers", {})
        headers.update(self.headers)
        return client.post(url, headers=headers, **kwargs)

auth_client = AuthClient(_get_test_token())


class MockHRBackend:
    def evaluate(self, question: HRQuestion, answer: str) -> HREvaluation:
        return HREvaluation(
            clarity=1.0, specificity=1.0, ownership=1.0, communication=1.0,
            teamwork=1.0, leadership=1.0, problem_solving=1.0,
            feedback="Mock feedback", overall_score=1.0
        )

@pytest.fixture
def mock_backend_for():
    with patch("app.routers.hr._backend_for", return_value=MockHRBackend()) as mock:
        yield mock


def test_full_hr_flow(mock_backend_for):
    # 1. Start
    start_resp = auth_client.post("/hr/start", json={
        "name": "Test Candidate",
        "target_role": "SWE Intern",
        "experience": "Intermediate",
        "max_questions": 2,
    })
    assert start_resp.status_code == 200
    session_id = start_resp.json()["session_id"]
    
    # 2. Answer 1
    answer1_resp = auth_client.post("/hr/answer", json={
        "session_id": session_id,
        "answer": "First answer"
    })
    assert answer1_resp.status_code == 200
    body1 = answer1_resp.json()
    assert not body1["completed"]
    assert body1["evaluation"]["overall_score"] == 1.0
    
    # 3. Answer 2
    answer2_resp = auth_client.post("/hr/answer", json={
        "session_id": session_id,
        "answer": "Second answer"
    })
    assert answer2_resp.status_code == 200
    body2 = answer2_resp.json()
    assert body2["completed"]
    
    # 4. Finish
    finish_resp = auth_client.post(f"/hr/finish/{session_id}")
    assert finish_resp.status_code == 200
    report = finish_resp.json()["report"]
    assert report["questions_answered"] == 2

def test_hr_auth_required():
    resp = client.post("/hr/start", json={
        "name": "Unauth", "target_role": "SWE", "experience": "Entry"
    })
    assert resp.status_code == 401

def test_unknown_session_returns_404():
    resp = auth_client.post("/hr/answer", json={"session_id": "does-not-exist", "answer": "x"})
    assert resp.status_code == 404

def test_cross_user_isolation(mock_backend_for):
    start_resp = auth_client.post("/hr/start", json={
        "name": "User 1", "target_role": "SWE", "experience": "Entry",
        "max_questions": 2
    })
    session_id = start_resp.json()["session_id"]
    
    auth_client_2 = AuthClient(_get_test_token("another-user-456"))
    resp = auth_client_2.post("/hr/answer", json={
        "session_id": session_id, "answer": "Stealing session"
    })
    assert resp.status_code == 404
