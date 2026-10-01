"""
Central configuration for the Mockexa FastAPI backend.

Every value that could plausibly change between environments (dev/staging/
Expo laptop) is read from an environment variable. Nothing here is a
hard-coded secret. GEMINI_API_KEY is read but never logged, never returned in
any response, and never sent to iOS.
"""
from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field

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
    # --- Google Gemini provider ---
    gemini_api_key: str | None = Field(
        default_factory=lambda: os.environ.get("GEMINI_API_KEY")
    )
    gemini_model: str = Field(
        default_factory=lambda: os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite")
    )
    gemini_fallback_model: str | None = Field(
        default_factory=lambda: os.environ.get("GEMINI_FALLBACK_MODEL", "gemini-2.5-flash")
    )
    gemini_timeout_seconds: float = _float_env("GEMINI_TIMEOUT_SECONDS", 20.0)
    gemini_max_retries: int = _int_env("GEMINI_MAX_RETRIES", 3)
    use_gemini: bool = _bool_env("USE_GEMINI", True)

    # Generic fallback budgets, used only if a task-specific budget below is unset.
    gemini_max_input_tokens: int = _int_env("GEMINI_MAX_INPUT_TOKENS", 4000)
    gemini_max_output_tokens: int = _int_env("GEMINI_MAX_OUTPUT_TOKENS", 512)

    # --- Task-specific token budgets (PROJECT_STATUS.md: "prefer separate settings") ---
    gd_generation_max_input_tokens: int = _int_env("GD_GENERATION_MAX_INPUT_TOKENS", 3000)
    gd_generation_max_output_tokens: int = _int_env("GD_GENERATION_MAX_OUTPUT_TOKENS", 160)

    technical_eval_max_input_tokens: int = _int_env("TECHNICAL_EVAL_MAX_INPUT_TOKENS", 2500)
    technical_eval_max_output_tokens: int = _int_env("TECHNICAL_EVAL_MAX_OUTPUT_TOKENS", 300)

    hr_eval_max_input_tokens: int = _int_env("HR_EVAL_MAX_INPUT_TOKENS", 2500)
    hr_eval_max_output_tokens: int = _int_env("HR_EVAL_MAX_OUTPUT_TOKENS", 450)

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
    # Set to "gemini" to route GD AI turns through Google Gemini.
    # Set to "local" to restore the local Qwen LoRA backend when performance allows.
    gd_generation_backend: str = os.environ.get("GD_GENERATION_BACKEND", "gemini")
    gd_verify_opening_turn: bool = _bool_env("GD_VERIFY_OPENING_TURN", False)

    # --- ElevenLabs Neural TTS Provider ---
    # Use a factory so a fresh Settings instance observes environment changes.
    # This also keeps test overrides isolated from a real key loaded at import.
    elevenlabs_api_key: str | None = Field(
        default_factory=lambda: os.environ.get("ELEVENLABS_API_KEY")
    )
    # Prefer the quality model for interview/GD speech. Flash is quicker, but
    # can produce brittle or metallic delivery on longer conversational text.
    elevenlabs_model_id: str = os.environ.get("ELEVENLABS_MODEL_ID", "eleven_multilingual_v2")
    elevenlabs_output_format: str = os.environ.get("ELEVENLABS_OUTPUT_FORMAT", "mp3_44100_128")
    tts_cache_ttl_seconds: int = _int_env("TTS_CACHE_TTL_SECONDS", 3600)
    tts_cache_max_entries: int = _int_env("TTS_CACHE_MAX_ENTRIES", 128)
    elevenlabs_voice_maya: str = os.environ.get("ELEVENLABS_VOICE_MAYA", "EXAVITQu4vr4xnSDxMaL")
    elevenlabs_voice_jordan: str = os.environ.get("ELEVENLABS_VOICE_JORDAN", "21m00Tcm4TlvDq8ikWAM")
    elevenlabs_voice_arjun: str = os.environ.get("ELEVENLABS_VOICE_ARJUN", "ErXwobaYiN019PkySvjV")
    elevenlabs_voice_elena: str = os.environ.get("ELEVENLABS_VOICE_ELENA", "MF3mGyEYCl7XYWbV9V6O")
    elevenlabs_voice_hr: str = os.environ.get("ELEVENLABS_VOICE_HR", "XrExE9yKIg1WjnnlVkGX")

    model_config = ConfigDict(frozen=True)


@lru_cache
def get_settings() -> Settings:
    return Settings()
