from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user_id, get_raw_jwt_token
from app.repository import RepositoryError, SupabaseRepository
from app.schemas.resume_cloud import ResumeCloudDocument, ResumeCloudSaveRequest


router = APIRouter(prefix="/resume-profiles", tags=["resume profiles"])
MAX_DOCUMENT_BYTES = 750_000


@router.get("", response_model=ResumeCloudDocument)
async def get_resume_profiles(
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
):
    try:
        row = await SupabaseRepository().resume_document(user_id, raw_token)
    except RepositoryError as exc:
        raise HTTPException(status_code=503, detail=f"Resume cloud storage unavailable: {exc}") from exc
    if row is None:
        return ResumeCloudDocument()
    return ResumeCloudDocument(
        profiles=row.get("profiles") or [],
        active_profile_id=row.get("active_profile_id"),
        updated_at=str(row.get("updated_at")) if row.get("updated_at") else None,
    )


@router.post("", response_model=ResumeCloudDocument)
async def save_resume_profiles(
    request: ResumeCloudSaveRequest,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
):
    encoded = json.dumps(request.profiles, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(encoded) > MAX_DOCUMENT_BYTES:
        raise HTTPException(status_code=413, detail="Resume profiles exceed the 750 KB cloud limit")
    profile_ids = {str(profile.get("id") or "") for profile in request.profiles}
    if request.active_profile_id and request.active_profile_id not in profile_ids:
        raise HTTPException(status_code=422, detail="active_profile_id must refer to a saved profile")
    try:
        repo = SupabaseRepository()
        await repo.ensure_profile(user_id, raw_token)
        row = await repo.upsert_resume_document({
            "user_id": user_id,
            "profiles": request.profiles,
            "active_profile_id": request.active_profile_id,
        }, raw_token)
    except RepositoryError as exc:
        raise HTTPException(status_code=503, detail=f"Resume cloud storage unavailable: {exc}") from exc
    return ResumeCloudDocument(
        profiles=row.get("profiles") or [],
        active_profile_id=row.get("active_profile_id"),
        updated_at=str(row.get("updated_at")) if row.get("updated_at") else None,
    )
