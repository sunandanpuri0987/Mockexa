from __future__ import annotations

import os
import logging
import hashlib
import time
from collections import OrderedDict
import httpx
from pydantic import BaseModel, Field
from fastapi import APIRouter, HTTPException, status
from fastapi.responses import Response

from app.config import get_settings

logger = logging.getLogger("prepai.tts")

router = APIRouter(prefix="/tts", tags=["TTS"])

# Small process-local cache: GD responses are often replayed when a view is
# redrawn or the user taps replay. Avoid charging for and waiting on identical
# ElevenLabs generations. This is intentionally bounded and contains audio
# only; it can later be replaced by Redis/object storage for multiple workers.
_tts_cache: OrderedDict[str, tuple[float, bytes, str]] = OrderedDict()
_elevenlabs_disabled_until: float = 0.0
_elevenlabs_disabled_key: str | None = None


def _elevenlabs_available(api_key: str) -> bool:
    """Retry a failed provider after a short cooldown or when its key changes."""
    global _elevenlabs_disabled_until, _elevenlabs_disabled_key
    key_fingerprint = hashlib.sha256(api_key.encode("utf-8")).hexdigest()
    if _elevenlabs_disabled_key != key_fingerprint:
        _elevenlabs_disabled_key = key_fingerprint
        _elevenlabs_disabled_until = 0.0
    return time.monotonic() >= _elevenlabs_disabled_until


def _cooldown_elevenlabs(seconds: float) -> None:
    global _elevenlabs_disabled_until
    _elevenlabs_disabled_until = time.monotonic() + seconds

import re

class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=2000)
    speaker: str = Field(default="Dr. Maya Shah")
    voice_id: str | None = Field(default=None)

# Fallback OpenAI voice mapping
OPENAI_VOICE_MAP = {
    "maya": "nova",       # Calm, professional female
    "jordan": "echo",      # Conversational, thoughtful male
    "arjun": "alloy",      # Energetic, articulate male
    "elena": "fable",      # Composed, structured female
    "hr": "nova",          # Warm, professional interviewer
}

# Persona-specific ElevenLabs voice parameters for distinct natural delivery
ELEVENLABS_PERSONA_VOICE_SETTINGS = {
    # Conservative settings avoid the metallic artefacts and abrupt prosody
    # that can occur when Flash is driven with very low stability/high style.
    "maya": {"stability": 0.72, "similarity_boost": 0.80, "style": 0.05, "speed": 0.98, "use_speaker_boost": True},
    "jordan": {"stability": 0.66, "similarity_boost": 0.78, "style": 0.08, "speed": 0.98, "use_speaker_boost": True},
    "arjun": {"stability": 0.62, "similarity_boost": 0.76, "style": 0.10, "speed": 1.00, "use_speaker_boost": True},
    "elena": {"stability": 0.70, "similarity_boost": 0.82, "style": 0.06, "speed": 0.98, "use_speaker_boost": True},
    "hr": {"stability": 0.68, "similarity_boost": 0.82, "style": 0.08, "speed": 0.98, "use_speaker_boost": True},
}


def _cache_key(text: str, voice_id: str, model_id: str, output_format: str, settings: dict) -> str:
    raw = f"{voice_id}\0{model_id}\0{output_format}\0{text}\0{settings}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _cached_audio(key: str, ttl_seconds: int) -> tuple[bytes, str] | None:
    item = _tts_cache.get(key)
    if item is None:
        return None
    created_at, audio, provider = item
    if time.monotonic() - created_at > ttl_seconds:
        _tts_cache.pop(key, None)
        return None
    _tts_cache.move_to_end(key)
    return audio, provider


def _store_audio(key: str, audio: bytes, provider: str, max_entries: int) -> None:
    _tts_cache[key] = (time.monotonic(), audio, provider)
    _tts_cache.move_to_end(key)
    while len(_tts_cache) > max(1, max_entries):
        _tts_cache.popitem(last=False)

def sanitize_text_for_tts(raw_text: str) -> str:
    """
    Sanitize text before TTS synthesis by stripping markdown formatting,
    bullet points, headers, emojis, and normalizing pauses.
    Display transcript remains untouched.
    """
    if not raw_text:
        return ""
    # Strip markdown headers (### Header -> Header)
    cleaned = re.sub(r'#+\s*', '', raw_text)
    # Strip markdown bold/italic (**text** or *text*)
    cleaned = re.sub(r'\*+([^*]+)\*+', r'\1', cleaned)
    cleaned = re.sub(r'_+([^_]+)_+', r'\1', cleaned)
    # Strip bullet point symbols at start of lines
    cleaned = re.sub(r'^\s*[-•*]\s+', '', cleaned, flags=re.MULTILINE)
    # Strip numbered list prefixes (1. 2. etc)
    cleaned = re.sub(r'^\s*\d+\.\s+', '', cleaned, flags=re.MULTILINE)
    # Convert line breaks to pauses
    cleaned = re.sub(r'\n+', '. ', cleaned)
    # Collapse multiple whitespace
    cleaned = re.sub(r'\s+', ' ', cleaned)
    # Normalize double periods
    cleaned = re.sub(r'\.{2,}', '.', cleaned)
    return cleaned.strip()

@router.post("", response_class=Response)
async def generate_tts(body: TTSRequest):
    """
    Generate neural TTS audio for GD and interview flows using backend-held credentials.
    Returns binary audio/mpeg MP3 bytes.
    """
    clean_text = sanitize_text_for_tts(body.text)
    if not clean_text:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty text after sanitization")
        
    settings = get_settings()
    speaker_norm = body.speaker.lower()
    voice_key = "maya"
    if "hr interviewer" in speaker_norm or "recruiter" in speaker_norm:
        voice_key = "hr"
    elif "jordan" in speaker_norm or "lee" in speaker_norm:
        voice_key = "jordan"
    elif "arjun" in speaker_norm or "mehta" in speaker_norm:
        voice_key = "arjun"
    elif "elena" in speaker_norm or "ruiz" in speaker_norm:
        voice_key = "elena"
        
    eleven_key = settings.elevenlabs_api_key or os.getenv("ELEVENLABS_API_KEY")
    openai_key = os.getenv("OPENAI_API_KEY")
    
    if eleven_key and _elevenlabs_available(eleven_key):
        if body.voice_id:
            eleven_voice_id = body.voice_id
        else:
            voice_map = {
                "maya": os.getenv("ELEVENLABS_VOICE_MAYA") or settings.elevenlabs_voice_maya,
                "jordan": os.getenv("ELEVENLABS_VOICE_JORDAN") or settings.elevenlabs_voice_jordan,
                "arjun": os.getenv("ELEVENLABS_VOICE_ARJUN") or settings.elevenlabs_voice_arjun,
                "elena": os.getenv("ELEVENLABS_VOICE_ELENA") or settings.elevenlabs_voice_elena,
                "hr": os.getenv("ELEVENLABS_VOICE_HR") or settings.elevenlabs_voice_hr,
            }
            eleven_voice_id = voice_map.get(voice_key, settings.elevenlabs_voice_maya)
            
        persona_settings = ELEVENLABS_PERSONA_VOICE_SETTINGS.get(
            voice_key,
            {"stability": 0.55, "similarity_boost": 0.75, "style": 0.10, "use_speaker_boost": True}
        )
            
        output_format = settings.elevenlabs_output_format
        cache_key = _cache_key(
            clean_text,
            eleven_voice_id,
            settings.elevenlabs_model_id,
            output_format,
            persona_settings,
        )
        cached = _cached_audio(cache_key, settings.tts_cache_ttl_seconds)
        if cached is not None:
            audio, provider = cached
            logger.info("[VOICE][TTS] provider=%s speaker=%s cache=hit audio_bytes=%d", provider, body.speaker, len(audio))
            return Response(content=audio, media_type="audio/mpeg", headers={"X-TTS-Cache": "HIT", "X-TTS-Provider": provider})

        # The streaming HTTP endpoint has a lower time-to-first-byte than the
        # regular endpoint. The backend currently returns a complete MP3 to the
        # iOS AVAudioPlayer, while Flash keeps generation itself low latency.
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{eleven_voice_id}/stream"
        headers = {
            "xi-api-key": eleven_key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg"
        }
        payload = {
            "text": clean_text,
            "model_id": settings.elevenlabs_model_id,
            "voice_settings": persona_settings
        }
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                res = await client.post(
                    url,
                    params={"output_format": output_format},
                    json=payload,
                    headers=headers,
                )
                if res.status_code == 200:
                    logger.info("[VOICE][TTS] provider=ElevenLabs speaker=%s voice_id=%s status=%d audio_bytes=%d", body.speaker, eleven_voice_id, res.status_code, len(res.content))
                    _store_audio(cache_key, res.content, "ElevenLabs", settings.tts_cache_max_entries)
                    return Response(
                        content=res.content,
                        media_type="audio/mpeg",
                        headers={"X-TTS-Cache": "MISS", "X-TTS-Provider": "ElevenLabs"},
                    )
                else:
                    if res.status_code in (401, 402, 403):
                        # ElevenLabs reports exhausted account quota as 401.
                        # Avoid retrying every sentence while still recovering
                        # automatically after a top-up or key change.
                        _cooldown_elevenlabs(300.0 if "quota_exceeded" in res.text else 60.0)
                    logger.warning("[VOICE][TTS] provider=ElevenLabs speaker=%s status=%d error=%s. Bypassing ElevenLabs.", body.speaker, res.status_code, res.text[:120])
        except Exception as e:
            _cooldown_elevenlabs(10.0)
            logger.warning("[VOICE][TTS] provider=ElevenLabs speaker=%s error=%s. Bypassing ElevenLabs.", body.speaker, str(e))
            
    if openai_key:
        openai_voice = OPENAI_VOICE_MAP.get(voice_key, "nova")
        url = "https://api.openai.com/v1/audio/speech"
        headers = {
            "Authorization": f"Bearer {openai_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": "tts-1",
            "input": clean_text,
            "voice": openai_voice,
            "response_format": "mp3"
        }
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                res = await client.post(url, json=payload, headers=headers)
                if res.status_code == 200:
                    logger.info("[VOICE][TTS] provider=OpenAI speaker=%s voice=%s status=%d audio_bytes=%d", body.speaker, openai_voice, res.status_code, len(res.content))
                    return Response(content=res.content, media_type="audio/mpeg", headers={"X-TTS-Cache": "MISS", "X-TTS-Provider": "OpenAI"})
                else:
                    logger.warning("[VOICE][TTS] provider=OpenAI speaker=%s status=%d error=%s. Falling back to EdgeTTS.", body.speaker, res.status_code, res.text[:200])
        except Exception as e:
            logger.warning("[VOICE][TTS] provider=OpenAI speaker=%s error=%s. Falling back to EdgeTTS.", body.speaker, str(e))

    # Resilient high-quality fallback via EdgeTTS (unlimited, zero-quota)
    try:
        import edge_tts
        edge_voice_map = {
            "maya": "en-US-JennyNeural",
            "jordan": "en-US-GuyNeural",
            "arjun": "en-IN-PrabhatNeural",
            "elena": "en-US-AriaNeural",
            "hr": "en-US-JennyNeural",
        }
        selected_voice = edge_voice_map.get(voice_key, "en-US-JennyNeural")
        communicate = edge_tts.Communicate(clean_text, selected_voice)
        audio_chunks = []
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_chunks.append(chunk["data"])
        edge_audio = b"".join(audio_chunks)
        if edge_audio:
            logger.info("[VOICE][TTS] provider=EdgeTTS speaker=%s voice=%s audio_bytes=%d", body.speaker, selected_voice, len(edge_audio))
            return Response(content=edge_audio, media_type="audio/mpeg", headers={"X-TTS-Cache": "MISS", "X-TTS-Provider": "EdgeTTS"})
    except Exception as edge_err:
        logger.error("[VOICE][TTS] EdgeTTS fallback failed: %s", str(edge_err))

    raise HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail="All TTS providers (ElevenLabs, OpenAI, EdgeTTS) failed to synthesize audio."
    )
