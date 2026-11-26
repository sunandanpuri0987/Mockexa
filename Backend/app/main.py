from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings, validate_production_settings
from app.error_handlers import register_error_handlers
from app.routers import account, aptitude, company, gd, health, hr, legal, resume_cloud, sessions, technical, tts
from app.security import install_security_middleware

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("mockexa.app")

_settings = get_settings()
validate_production_settings(_settings)

app = FastAPI(
    title="Mockexa Backend",
    version="0.2.0",
    description=(
        "Backend API for the Mockexa interview preparation platform.\n\n"
        "**Implemented:** Technical Interview, HR Interview, Group Discussion, Aptitude Round, Company Practice, Health Check, Sessions History, Neural TTS.\n\n"
        "**Authentication:** JWT Bearer token required for interview & sessions routes. "
        "Send `Authorization: Bearer <token>` header. "
        "Tokens are issued by Supabase Auth (or HS256 JWT signer sharing secret).\n\n"
        "`/health` is unauthenticated."
    ),
)

# --- CORS ---
_origins = [o.strip() for o in _settings.cors_origins.split(",") if o.strip()]
if "*" in _origins and _settings.environment != "development":
    logger.warning(
        "CORS_ORIGINS is set to '*' outside development (env=%s). "
        "Restrict this before deploying to production.",
        _settings.environment,
    )
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
install_security_middleware(app, _settings)

# --- Error handlers ---
register_error_handlers(app)


@app.get("/", tags=["health"])
def root():
    """Friendly landing response for local development and uptime checks."""
    return {
        "status": "ok",
        "service": "Mockexa Backend",
        "health": "/health",
        "docs": "/docs",
    }

# --- Routers ---
app.include_router(health.router)
app.include_router(technical.router)
app.include_router(gd.router)
app.include_router(hr.router)
app.include_router(sessions.router)
app.include_router(tts.router)
app.include_router(company.router)
app.include_router(aptitude.router)
app.include_router(resume_cloud.router)
app.include_router(account.router)
app.include_router(legal.router)
