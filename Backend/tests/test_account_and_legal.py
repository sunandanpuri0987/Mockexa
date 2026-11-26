import os
import time
from unittest.mock import patch

import jwt
from fastapi.testclient import TestClient

from app.main import app
from app.repository import RepositoryError


client = TestClient(app)
TEST_SECRET = os.environ.get(
    "SUPABASE_JWT_SECRET", "dev-secret-do-not-use-in-production-replace-with-supabase-jwt-secret"
)


def _token(user_id: str = "account-delete-user") -> str:
    return jwt.encode({"sub": user_id, "exp": time.time() + 3600}, TEST_SECRET, algorithm="HS256")


class _DeletingRepository:
    async def delete_own_account(self, token: str) -> bool:
        return bool(token)


class _FailingRepository:
    async def delete_own_account(self, token: str) -> bool:
        raise RepositoryError("database unavailable")


def test_account_deletion_requires_authentication():
    response = client.delete("/account")
    assert response.status_code in (401, 403)


def test_account_deletion_calls_user_scoped_rpc():
    with patch("app.routers.account.SupabaseRepository", return_value=_DeletingRepository()):
        response = client.delete("/account", headers={"Authorization": f"Bearer {_token()}"})
    assert response.status_code == 200
    assert response.json()["deleted"] is True
    assert "permanently deleted" in response.json()["message"]


def test_account_deletion_reports_storage_failure_without_claiming_success():
    with patch("app.routers.account.SupabaseRepository", return_value=_FailingRepository()):
        response = client.delete("/account", headers={"Authorization": f"Bearer {_token()}"})
    assert response.status_code == 503
    assert "Account deletion unavailable" in response.json()["detail"]


def test_legal_pages_are_public_and_contain_required_topics():
    privacy = client.get("/legal/privacy")
    terms = client.get("/legal/terms")
    assert privacy.status_code == 200
    assert terms.status_code == 200
    assert "account and associated cloud data" in privacy.text
    assert "Service providers" in privacy.text
    assert "AI-generated content" in terms.text
