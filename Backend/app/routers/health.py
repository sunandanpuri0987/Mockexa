from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.config import Settings, get_settings

router = APIRouter(tags=["health"])


class HealthResponse(BaseModel):
    status: str
    environment: str
    groq_configured: bool


@router.get("/health", response_model=HealthResponse)
def health(settings: Settings = Depends(get_settings)):
    return HealthResponse(
        status="ok",
        environment=settings.environment,
        groq_configured=bool(settings.groq_api_key),
    )

