"""
Central configuration for the Mockexa FastAPI backend.

Every value that could plausibly change between environments (dev/staging/
Expo laptop) is read from an environment variable. Nothing here is a
hard-coded secret. GROQ_API_KEY is read but never logged, never returned in
any response, and never sent to iOS.
"""
from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel, ConfigDict

# Load .env from the project root (the directory containing this package).
# override=False preserves values already set in the real environment
# (e.g. from uvicorn --env-file, CI secrets, or Docker secrets), so this
# never silently overwrites a real deployment value.
try:
    from dotenv import load_dotenv  # python-dotenv is already a project dependency
    load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=False)
except ImportError:
    pass  # python-dotenv not installed; rely on environment variables alone


def _int_env(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _float_env(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _bool_env(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return raw.lower() in ("true", "1", "yes", "on")


class Settings(BaseModel):
    # --- Groq provider ---
    groq_api_key: str | None = os.environ.get("GROQ_API_KEY")
    groq_model: str = os.environ.get("GROQ_MODEL", "llama-3.1-8b-instant")
    groq_timeout_seconds: float = _float_env("GROQ_TIMEOUT_SECONDS", 20.0)
    groq_max_retries: int = _int_env("GROQ_MAX_RETRIES", 3)
    use_groq: bool = _bool_env("USE_GROQ", False)

    # Generic fallback budgets, used only if a task-specific budget below is unset.
    groq_max_input_tokens: int = _int_env("GROQ_MAX_INPUT_TOKENS", 4000)
    groq_max_output_tokens: int = _int_env("GROQ_MAX_OUTPUT_TOKENS", 512)

    # --- Task-specific token budgets (PROJECT_STATUS.md: "prefer separate settings") ---
    gd_generation_max_input_tokens: int = _int_env("GD_GENERATION_MAX_INPUT_TOKENS", 3000)
    gd_generation_max_output_tokens: int = _int_env("GD_GENERATION_MAX_OUTPUT_TOKENS", 160)

    technical_eval_max_input_tokens: int = _int_env("TECHNICAL_EVAL_MAX_INPUT_TOKENS", 2500)
    technical_eval_max_output_tokens: int = _int_env("TECHNICAL_EVAL_MAX_OUTPUT_TOKENS", 300)

    hr_eval_max_input_tokens: int = _int_env("HR_EVAL_MAX_INPUT_TOKENS", 2500)
    hr_eval_max_output_tokens: int = _int_env("HR_EVAL_MAX_OUTPUT_TOKENS", 300)

    feedback_max_input_tokens: int = _int_env("FEEDBACK_MAX_INPUT_TOKENS", 3500)
    feedback_max_output_tokens: int = _int_env("FEEDBACK_MAX_OUTPUT_TOKENS", 400)

    # --- App ---
    environment: str = os.environ.get("PREPAI_ENV", "development")
    host: str = os.environ.get("HOST", "0.0.0.0")
    port: int = _int_env("PORT", 8000)
    cors_origins: str = os.environ.get("CORS_ORIGINS", "*")

    # --- Auth (Supabase-compatible JWT) ---
    supabase_url: str | None = os.environ.get("SUPABASE_URL")
    supabase_anon_key: str | None = os.environ.get("SUPABASE_ANON_KEY")
    supabase_jwt_secret: str | None = os.environ.get("SUPABASE_JWT_SECRET")

    # --- Feature Flags ---
    use_supabase_persistence: bool = _bool_env("USE_SUPABASE_PERSISTENCE", False)

    # --- GD Generation Provider ---
    # Set to "groq" to route GD AI turns through Groq (fast, for demo/testing).
    # Set to "local" to restore the local Qwen LoRA backend when performance allows.
    gd_generation_backend: str = os.environ.get("GD_GENERATION_BACKEND", "groq")

    model_config = ConfigDict(frozen=True)


@lru_cache
def get_settings() -> Settings:
    return Settings()
