from __future__ import annotations

from app.routers import resume_cloud


class FakeResumeRepository:
    def __init__(self):
        self.rows: dict[str, dict] = {}

    async def ensure_profile(self, user_id: str, token: str) -> dict:
        return {"id": user_id}

    async def resume_document(self, user_id: str, token: str) -> dict | None:
        return self.rows.get(user_id)

    async def upsert_resume_document(self, data: dict, token: str) -> dict:
        row = {**data, "updated_at": "2026-11-26T12:00:00Z"}
        self.rows[data["user_id"]] = row
        return row


def test_resume_profiles_round_trip_and_owner_isolation(client, auth_headers, second_auth_headers, monkeypatch):
    repository = FakeResumeRepository()
    monkeypatch.setattr(resume_cloud, "SupabaseRepository", lambda: repository)
    payload = {
        "profiles": [{
            "id": "resume-1",
            "name": "My Resume",
            "resumeData": {"summary": "Swift and FastAPI engineer"},
            "updatedAt": 817344000,
        }],
        "active_profile_id": "resume-1",
    }
    saved = client.post("/resume-profiles", headers=auth_headers, json=payload)
    assert saved.status_code == 200
    assert saved.json()["profiles"] == payload["profiles"]
    assert saved.json()["active_profile_id"] == "resume-1"

    loaded = client.get("/resume-profiles", headers=auth_headers)
    assert loaded.status_code == 200
    assert loaded.json()["profiles"] == payload["profiles"]

    other_user = client.get("/resume-profiles", headers=second_auth_headers)
    assert other_user.status_code == 200
    assert other_user.json()["profiles"] == []


def test_resume_profiles_reject_invalid_active_id(client, auth_headers, monkeypatch):
    monkeypatch.setattr(resume_cloud, "SupabaseRepository", FakeResumeRepository)
    response = client.post("/resume-profiles", headers=auth_headers, json={
        "profiles": [{"id": "resume-1", "name": "Resume"}],
        "active_profile_id": "missing",
    })
    assert response.status_code == 422


def test_resume_profiles_require_auth(client):
    assert client.get("/resume-profiles").status_code in (401, 403)
