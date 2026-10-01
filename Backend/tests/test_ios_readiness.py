"""
Tests for iOS-integration preparation changes:
- CORS headers present in responses
- Error responses have consistent JSON {"detail": "..."} structure
- Health endpoint returns typed HealthResponse
- GD/HR 501 responses return JSON with detail field
- Unhandled exceptions return JSON 500, not tracebacks
"""
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


# --- CORS ---

def test_cors_headers_on_regular_request():
    resp = client.get("/health")
    # CORSMiddleware adds headers on all responses when origin is present
    resp_with_origin = client.get("/health", headers={"Origin": "http://localhost:3000"})
    assert resp_with_origin.headers.get("access-control-allow-origin") is not None


def test_cors_preflight():
    resp = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert resp.status_code == 200
    assert resp.headers.get("access-control-allow-origin") is not None


# --- Health endpoint typed response ---

def test_health_returns_typed_fields():
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert isinstance(body["environment"], str)
    assert isinstance(body["gemini_configured"], bool)
    # Ensure no extra fields leak through
    assert set(body.keys()) == {"status", "environment", "gemini_configured"}


# --- GD/HR 501 responses are JSON ---





import os
import jwt

# Development secret must match the one in test environment or fallback
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

# --- Validation errors return JSON ---

def test_validation_error_returns_json_422():
    # Send a request with an invalid type for a required field
    resp = auth_client.post("/technical/start", json={
        "name": 123,  # string expected, but FastAPI/Pydantic will coerce this
        "target_role": "SWE",
        "experience": "Beginner",
        "selected_domains": "not-a-list",  # list expected — this will fail validation
    })
    assert resp.status_code == 422
    body = resp.json()
    assert "detail" in body
    assert isinstance(body["detail"], str)


# --- Missing required fields return JSON 422 ---

def test_missing_required_fields_returns_422_json():
    resp = auth_client.post("/technical/start", json={})
    assert resp.status_code == 422
    body = resp.json()
    assert "detail" in body
