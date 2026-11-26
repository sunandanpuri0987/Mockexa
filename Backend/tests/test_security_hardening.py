from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest

from app.config import Settings, validate_production_settings
from app.security import install_security_middleware


def _test_app(**settings_updates) -> TestClient:
    app = FastAPI()
    settings = Settings().model_copy(update=settings_updates)
    install_security_middleware(app, settings)

    @app.post("/echo")
    async def echo():
        return {"ok": True}

    return TestClient(app)


def test_api_responses_include_security_and_request_id_headers(client):
    response = client.get("/health", headers={"X-Request-ID": "test-request-123"})
    assert response.status_code == 200
    assert response.headers["x-request-id"] == "test-request-123"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert response.headers["cache-control"] == "no-store"


def test_invalid_request_id_is_replaced(client):
    response = client.get("/health", headers={"X-Request-ID": "bad id"})
    assert response.status_code == 200
    assert response.headers["x-request-id"] != "bad id"
    assert len(response.headers["x-request-id"]) >= 32


def test_declared_oversized_body_is_rejected():
    client = _test_app(max_request_body_bytes=16)
    response = client.post("/echo", content=b"x" * 17)
    assert response.status_code == 413
    assert response.json() == {"detail": "Request body is too large."}


def test_rate_limit_returns_retry_after_without_storing_raw_token():
    client = _test_app(
        enable_rate_limiting=True,
        rate_limit_requests=1,
        rate_limit_window_seconds=60,
    )
    headers = {"Authorization": "Bearer private-value"}
    assert client.post("/echo", headers=headers).status_code == 200
    limited = client.post("/echo", headers=headers)
    assert limited.status_code == 429
    assert int(limited.headers["retry-after"]) >= 1


def test_production_configuration_fails_closed_when_unsafe():
    settings = Settings().model_copy(update={
        "environment": "production",
        "cors_origins": "*",
        "supabase_url": None,
        "supabase_anon_key": None,
        "use_supabase_persistence": False,
        "enable_rate_limiting": False,
    })
    with pytest.raises(RuntimeError, match="Unsafe production configuration"):
        validate_production_settings(settings)


def test_production_configuration_accepts_explicit_secure_values():
    settings = Settings().model_copy(update={
        "environment": "production",
        "cors_origins": "https://app.mockexa.example",
        "supabase_url": "https://project.supabase.co",
        "supabase_anon_key": "public-anon-key",
        "use_supabase_persistence": True,
        "enable_rate_limiting": True,
        "max_request_body_bytes": 1_000_000,
        "rate_limit_requests": 120,
        "rate_limit_window_seconds": 60,
    })
    validate_production_settings(settings)
