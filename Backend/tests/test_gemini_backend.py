from unittest.mock import MagicMock

import pytest

from app.config import Settings
from app.providers.gemini_backend import GeminiBackend
from app.providers.llm_backend import (
    GenerationRequest, LLMBackendError, LLMBudgetExceededError,
    LLMMalformedResponseError, LLMRateLimitedError, LLMTransientError,
)


def make_settings(**overrides) -> Settings:
    values = dict(
        gemini_api_key="test-key", gemini_model="test-model",
        gemini_timeout_seconds=5.0, gemini_max_retries=2,
        gemini_max_input_tokens=1000, gemini_max_output_tokens=200,
        gd_generation_max_input_tokens=1000, gd_generation_max_output_tokens=200,
        technical_eval_max_input_tokens=1000, technical_eval_max_output_tokens=200,
        hr_eval_max_input_tokens=1000, hr_eval_max_output_tokens=200,
        feedback_max_input_tokens=1000, feedback_max_output_tokens=200,
    )
    values.update(overrides)
    return Settings(**values)


def generation_request() -> GenerationRequest:
    return GenerationRequest(
        task="technical_eval", system_prompt="system", user_prompt="hello",
        max_output_tokens=100,
    )


def response(text: str, status_code=200):
    mock = MagicMock()
    mock.status_code = status_code
    mock.headers = {}
    mock.json.return_value = {
        "candidates": [{"content": {"parts": [{"text": text}]}}],
        "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 5},
    }
    return mock


def test_successful_generation_returns_text_and_usage():
    client = MagicMock()
    client.post.return_value = response("hello world")
    result = GeminiBackend(make_settings(), client=client).generate(generation_request())
    assert result.text == "hello world"
    assert result.provider == "gemini"
    assert result.input_tokens == 10
    assert result.output_tokens == 5
    assert result.retry_count == 0
    _, kwargs = client.post.call_args
    assert kwargs["headers"]["x-goog-api-key"] == "test-key"
    assert kwargs["json"]["systemInstruction"]["parts"][0]["text"] == "system"


def test_input_budget_exceeded_raises_before_any_call():
    client = MagicMock()
    backend = GeminiBackend(make_settings(gemini_max_input_tokens=1), client=client)
    with pytest.raises(LLMBudgetExceededError):
        backend.generate(generation_request())
    client.post.assert_not_called()


def test_missing_key_fails_without_call():
    client = MagicMock()
    backend = GeminiBackend(make_settings(gemini_api_key=None), client=client)
    with pytest.raises(LLMBackendError, match="GEMINI_API_KEY"):
        backend.generate(generation_request())
    client.post.assert_not_called()


@pytest.mark.parametrize("status,error_type", [(500, LLMTransientError), (429, LLMRateLimitedError)])
def test_retryable_errors_exhaust_retries(monkeypatch, status, error_type):
    monkeypatch.setattr("app.providers.gemini_backend.time.sleep", lambda _: None)
    client = MagicMock()
    client.post.side_effect = [response("", status), response("", status)]
    with pytest.raises(error_type):
        GeminiBackend(make_settings(), client=client).generate(generation_request())
    assert client.post.call_count == 2


def test_retries_then_succeeds(monkeypatch):
    monkeypatch.setattr("app.providers.gemini_backend.time.sleep", lambda _: None)
    client = MagicMock()
    client.post.side_effect = [response("", 503), response("recovered")]
    result = GeminiBackend(make_settings(), client=client).generate(generation_request())
    assert result.text == "recovered"
    assert result.retry_count == 1


def test_rate_limit_switches_to_fallback_model(monkeypatch):
    monkeypatch.setattr("app.providers.gemini_backend.time.sleep", lambda _: None)
    client = MagicMock()
    client.post.side_effect = [response("", 429), response("fallback recovered")]
    settings = make_settings(
        gemini_model="primary-model",
        gemini_fallback_model="fallback-model",
        gemini_max_retries=2,
    )

    result = GeminiBackend(settings, client=client).generate(generation_request())

    assert result.text == "fallback recovered"
    assert result.model == "fallback-model"
    assert "primary-model:generateContent" in client.post.call_args_list[0].args[0]
    assert "fallback-model:generateContent" in client.post.call_args_list[1].args[0]


def test_empty_response_retries_then_raises(monkeypatch):
    monkeypatch.setattr("app.providers.gemini_backend.time.sleep", lambda _: None)
    client = MagicMock()
    client.post.side_effect = [response(""), response("   ")]
    with pytest.raises(LLMMalformedResponseError):
        GeminiBackend(make_settings(), client=client).generate(generation_request())


def test_non_retryable_error_fails_fast():
    client = MagicMock()
    client.post.return_value = response("", 400)
    with pytest.raises(LLMBackendError):
        GeminiBackend(make_settings(gemini_max_retries=3), client=client).generate(generation_request())
    assert client.post.call_count == 1
