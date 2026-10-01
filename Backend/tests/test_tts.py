from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app

client = TestClient(app)


def test_tts_without_configured_api_key_uses_edge_fallback(monkeypatch):
    get_settings.cache_clear()
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)

    class FakeEdgeTTS:
        def __init__(self, text, voice):
            assert text == "Hello GD team"
            assert voice == "en-US-JennyNeural"

        async def stream(self):
            yield {"type": "audio", "data": b"ID3_FAKE_EDGE_AUDIO"}

    with patch("edge_tts.Communicate", FakeEdgeTTS):
        response = client.post("/tts", json={"text": "Hello GD team", "speaker": "Dr. Maya Shah"})
    get_settings.cache_clear()
    assert response.status_code == 200
    assert response.headers["X-TTS-Provider"] == "EdgeTTS"
    assert response.content == b"ID3_FAKE_EDGE_AUDIO"


def test_tts_elevenlabs_success(monkeypatch):
    get_settings.cache_clear()
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-elevenlabs-key")

    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.content = b"ID3\x03\x00\x00\x00\x00\x00\x00FAKE_MP3_AUDIO_DATA"

    with patch("httpx.AsyncClient.post", return_value=mock_response) as mock_post:
        response = client.post("/tts", json={"text": "I agree with Arjun on this point.", "speaker": "Jordan Lee"})

        assert response.status_code == 200
        assert response.headers["content-type"] == "audio/mpeg"
        assert len(response.content) > 10
        assert response.content == b"ID3\x03\x00\x00\x00\x00\x00\x00FAKE_MP3_AUDIO_DATA"

        # Verify ElevenLabs API call
        assert mock_post.called
        call_kwargs = mock_post.call_args
        headers = call_kwargs.kwargs.get("headers", {})
        assert headers.get("xi-api-key") == "test-elevenlabs-key"
    get_settings.cache_clear()


def test_tts_elevenlabs_persona_voice_routing(monkeypatch):
    get_settings.cache_clear()


def test_tts_elevenlabs_hr_interviewer_voice_routing(monkeypatch):
    get_settings.cache_clear()
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-elevenlabs-key")
    monkeypatch.setenv("ELEVENLABS_VOICE_HR", "custom_hr_voice_id")

    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.content = b"AUDIO_HR_INTERVIEWER"

    with patch("httpx.AsyncClient.post", return_value=mock_response) as mock_post:
        response = client.post(
            "/tts",
            json={"text": "Tell me about a challenging project.", "speaker": "HR Interviewer"},
        )

        assert response.status_code == 200
        assert "custom_hr_voice_id" in mock_post.call_args.args[0]
    get_settings.cache_clear()
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-elevenlabs-key")
    monkeypatch.setenv("ELEVENLABS_VOICE_ARJUN", "custom_arjun_voice_id")

    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.content = b"AUDIO_ARJUN"

    with patch("httpx.AsyncClient.post", return_value=mock_response) as mock_post:
        response = client.post("/tts", json={"text": "Let us consider market scalability.", "speaker": "Arjun Mehta"})

        assert response.status_code == 200
        assert mock_post.called
        target_url = mock_post.call_args.args[0]
        assert "custom_arjun_voice_id" in target_url
    get_settings.cache_clear()


def test_tts_elevenlabs_error_returns_502(monkeypatch):
    get_settings.cache_clear()
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-invalid-key")
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)

    mock_response = AsyncMock()
    mock_response.status_code = 401
    mock_response.text = '{"detail":{"status":"invalid_api_key"}}'

    class FailedEdgeTTS:
        def __init__(self, text, voice):
            pass

        async def stream(self):
            raise RuntimeError("Edge TTS unavailable")
            yield  # Keep this an async generator.

    with patch("httpx.AsyncClient.post", return_value=mock_response), patch("edge_tts.Communicate", FailedEdgeTTS):
        response = client.post("/tts", json={"text": "Testing error state", "speaker": "Elena Ruiz"})

        assert response.status_code == 502
        assert "All TTS providers" in response.json()["detail"]
    get_settings.cache_clear()


def test_elevenlabs_cooldown_expires_and_new_key_retries(monkeypatch):
    from app.routers import tts

    clock = [100.0]
    monkeypatch.setattr(tts.time, "monotonic", lambda: clock[0])
    assert tts._elevenlabs_available("first-key")
    tts._cooldown_elevenlabs(60.0)
    assert not tts._elevenlabs_available("first-key")
    clock[0] = 161.0
    assert tts._elevenlabs_available("first-key")
    tts._cooldown_elevenlabs(60.0)
    assert tts._elevenlabs_available("rotated-key")
