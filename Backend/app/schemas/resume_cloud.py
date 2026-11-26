from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class ResumeCloudDocument(BaseModel):
    profiles: list[dict[str, Any]] = Field(default_factory=list, max_length=30)
    active_profile_id: str | None = Field(default=None, max_length=120)
    updated_at: str | None = None


class ResumeCloudSaveRequest(BaseModel):
    profiles: list[dict[str, Any]] = Field(default_factory=list, max_length=30)
    active_profile_id: str | None = Field(default=None, max_length=120)
