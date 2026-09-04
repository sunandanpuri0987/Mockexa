import os
import time

import jwt
from fastapi.testclient import TestClient

from app.main import app
from app.utils.session_store import technical_sessions

client = TestClient(app)

TEST_SECRET = os.environ.get(
    "SUPABASE_JWT_SECRET", "dev-secret-do-not-use-in-production-replace-with-supabase-jwt-secret"
)

def _get_token(user_id: str = "test-user-123", expired: bool = False, bad_secret: bool = False) -> str:
    payload = {"sub": user_id}
    if expired:
        payload["exp"] = time.time() - 3600
    else:
        payload["exp"] = time.time() + 3600
        
    secret = "wrong-secret" if bad_secret else TEST_SECRET
    return jwt.encode(payload, secret, algorithm="HS256")

def test_health_unauthenticated_succeeds():
    resp = client.get("/health")
    assert resp.status_code == 200

def test_missing_auth_returns_403(): # HTTPBearer returns 403 in older FastAPI, 401 in newer.
    resp = client.post("/technical/start", json={
        "name": "Test", "target_role": "SWE", "experience": "Intermediate"
    })
    assert resp.status_code in (401, 403)

def test_invalid_auth_returns_401():
    resp = client.post(
        "/technical/start", 
        headers={"Authorization": "Bearer not.a.real.jwt"},
        json={"name": "Test", "target_role": "SWE", "experience": "Intermediate"}
    )
    assert resp.status_code == 401
    assert resp.json() == {"detail": "Invalid authentication token."}

def test_bad_signature_returns_401():
    token = _get_token(bad_secret=True)
    resp = client.post(
        "/technical/start", 
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "Test", "target_role": "SWE", "experience": "Intermediate"}
    )
    assert resp.status_code == 401
    assert resp.json() == {"detail": "Invalid authentication token."}

def test_expired_token_returns_401():
    token = _get_token(expired=True)
    resp = client.post(
        "/technical/start", 
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "Test", "target_role": "SWE", "experience": "Intermediate"}
    )
    assert resp.status_code == 401
    assert resp.json() == {"detail": "Token has expired."}

def test_missing_sub_claim_returns_401():
    token = jwt.encode({"exp": time.time() + 3600}, TEST_SECRET, algorithm="HS256")
    resp = client.post(
        "/technical/start", 
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "Test", "target_role": "SWE", "experience": "Intermediate"}
    )
    assert resp.status_code == 401
    assert resp.json() == {"detail": "Invalid authentication token."}

def test_cross_user_session_access_denied():
    # User A starts session
    token_a = _get_token("user_A")
    start_resp = client.post(
        "/technical/start", 
        headers={"Authorization": f"Bearer {token_a}"},
        json={"name": "Test", "target_role": "SWE", "experience": "Intermediate"}
    )
    assert start_resp.status_code == 200
    session_id = start_resp.json()["session_id"]
    
    # Verify session is in store and owned by user_A
    assert technical_sessions._sessions[session_id].owner_user_id == "user_A"
    
    # User B tries to answer in User A's session
    token_b = _get_token("user_B")
    answer_resp = client.post(
        "/technical/answer", 
        headers={"Authorization": f"Bearer {token_b}"},
        json={"session_id": session_id, "answer": "Hello"}
    )
    # The load() fails because of ownership mismatch, resulting in a 404
    assert answer_resp.status_code == 404
    assert answer_resp.json() == {"detail": "unknown or expired session_id"}
    
    # User B tries to finish User A's session
    finish_resp = client.post(
        f"/technical/finish/{session_id}", 
        headers={"Authorization": f"Bearer {token_b}"}
    )
    assert finish_resp.status_code == 404

    # User A can successfully interact with their session
    answer_resp_a = client.post(
        "/technical/answer", 
        headers={"Authorization": f"Bearer {token_a}"},
        json={"session_id": session_id, "answer": "Hello"}
    )
    assert answer_resp_a.status_code == 200

# --- RS256 / JWKS tests ---
from unittest.mock import patch
from app.config import get_settings

import base64
import json

def _get_rs256_token(user_id: str = "test-user-123") -> str:
    # We manually construct a fake JWT with RS256 header to bypass PyJWT's strict RSA key validation during encode.
    header = {"alg": "RS256", "kid": "key-1"}
    payload = {"sub": user_id, "exp": time.time() + 3600}
    
    def b64_encode(d: dict) -> str:
        return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")
        
    return f"{b64_encode(header)}.{b64_encode(payload)}.fake"

def test_rs256_missing_supabase_url_returns_401():
    token = _get_rs256_token()
    settings = get_settings().model_copy(update={"supabase_url": None})
    app.dependency_overrides[get_settings] = lambda: settings
    try:
        resp = client.post(
            "/technical/start", 
            headers={"Authorization": f"Bearer {token}"},
            json={"name": "Test", "target_role": "SWE", "experience": "Intermediate"}
        )
        assert resp.status_code == 401
        assert "Unsupported token algorithm (RS256)" in resp.json()["detail"]
    finally:
        app.dependency_overrides.clear()

@patch("jwt.PyJWKClient")
def test_rs256_valid_token_succeeds(mock_jwk_client_class):
    from app.auth import _get_jwks_client
    _get_jwks_client.cache_clear()
    
    token = _get_rs256_token("rs256-user")
    
    mock_client_instance = mock_jwk_client_class.return_value
    mock_client_instance.get_signing_key_from_jwt.return_value.key = "fake-key"

    settings = get_settings().model_copy(update={"supabase_url": "https://test.supabase.co"})
    app.dependency_overrides[get_settings] = lambda: settings
    
    try:
        with patch("app.auth.jwt.decode", return_value={"sub": "rs256-user", "exp": time.time() + 3600}):
            resp = client.post(
                "/technical/start", 
                headers={"Authorization": f"Bearer {token}"},
                json={"name": "Test", "target_role": "SWE", "experience": "Intermediate"}
            )
            assert resp.status_code == 200
            assert mock_client_instance.get_signing_key_from_jwt.called
    finally:
        app.dependency_overrides.clear()

@patch("jwt.PyJWKClient")
def test_rs256_jwks_error_returns_401(mock_jwk_client_class):
    from app.auth import _get_jwks_client
    _get_jwks_client.cache_clear()
    
    token = _get_rs256_token()
    
    mock_client_instance = mock_jwk_client_class.return_value
    mock_client_instance.get_signing_key_from_jwt.side_effect = jwt.PyJWKClientError("Network error")

    settings = get_settings().model_copy(update={"supabase_url": "https://test.supabase.co"})
    app.dependency_overrides[get_settings] = lambda: settings
    
    try:
        resp = client.post(
            "/technical/start", 
            headers={"Authorization": f"Bearer {token}"},
            json={"name": "Test", "target_role": "SWE", "experience": "Intermediate"}
        )
        assert resp.status_code == 401
        assert resp.json()["detail"] == "Unable to verify token against identity provider."
    finally:
        app.dependency_overrides.clear()
