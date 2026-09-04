from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.config import Settings
from app.providers.groq_backend import GroqBackend
from app.providers.llm_backend import (
    GenerationRequest,
    LLMBudgetExceededError,
    LLMMalformedResponseError,
    LLMRateLimitedError,
    LLMTransientError,
)


def make_settings(**overrides) -> Settings:
    base = dict(
        groq_api_key="test-key",
        groq_model="test-model",
        groq_timeout_seconds=5.0,
        groq_max_retries=2,
        groq_max_input_tokens=1000,
        groq_max_output_tokens=200,
        gd_generation_max_input_tokens=1000, gd_generation_max_output_tokens=200,
        technical_eval_max_input_tokens=1000, technical_eval_max_output_tokens=200,
        hr_eval_max_input_tokens=1000, hr_eval_max_output_tokens=200,
        feedback_max_input_tokens=1000, feedback_max_output_tokens=200,
    )
    base.update(overrides)
    return Settings(**base)


def fake_response(text: str, prompt_tokens=10, completion_tokens=5):
    return SimpleNamespace(
        choices=[SimpleNamespace(message=SimpleNamespace(content=text))],
        usage=SimpleNamespace(prompt_tokens=prompt_tokens, completion_tokens=completion_tokens),
    )


def make_request(task="technical_eval"):
    return GenerationRequest(
        task=task, system_prompt="system", user_prompt="hello",
        max_output_tokens=100,
    )


def test_successful_generation_returns_text_and_usage():
    client = MagicMock()
    client.chat.completions.create.return_value = fake_response("hello world")
    backend = GroqBackend(make_settings(), client=client)

    result = backend.generate(make_request())

    assert result.text == "hello world"
    assert result.provider == "groq"
    assert result.input_tokens == 10
    assert result.output_tokens == 5
    assert result.retry_count == 0


def test_input_budget_exceeded_raises_before_any_call():
    client = MagicMock()
    settings = make_settings(groq_max_input_tokens=1)  # 1 token ~= 4 chars
    backend = GroqBackend(settings, client=client)

    with pytest.raises(LLMBudgetExceededError):
        backend.generate(make_request())
    client.chat.completions.create.assert_not_called()


def test_retries_on_transient_error_then_succeeds():
    client = MagicMock()
    error = Exception("server error")
    error.status_code = 503
    client.chat.completions.create.side_effect = [error, fake_response("recovered")]
    backend = GroqBackend(make_settings(), client=client)

    result = backend.generate(make_request())

    assert result.text == "recovered"
    assert result.retry_count == 1
    assert client.chat.completions.create.call_count == 2


def test_exhausts_retries_and_raises_transient_error():
    client = MagicMock()
    error = Exception("still down")
    error.status_code = 500
    client.chat.completions.create.side_effect = [error, error]
    backend = GroqBackend(make_settings(groq_max_retries=2), client=client)

    with pytest.raises(LLMTransientError):
        backend.generate(make_request())
    assert client.chat.completions.create.call_count == 2


def test_rate_limit_raises_after_exhausting_retries():
    client = MagicMock()
    error = Exception("rate limited")
    error.status_code = 429
    client.chat.completions.create.side_effect = [error, error]
    backend = GroqBackend(make_settings(groq_max_retries=2), client=client)

    with pytest.raises(LLMRateLimitedError):
        backend.generate(make_request())


def test_empty_response_retries_then_raises_malformed():
    client = MagicMock()
    client.chat.completions.create.side_effect = [fake_response(""), fake_response("   ")]
    backend = GroqBackend(make_settings(groq_max_retries=2), client=client)

    with pytest.raises(LLMMalformedResponseError):
        backend.generate(make_request())


def test_non_retryable_error_fails_fast_without_retry():
    client = MagicMock()
    error = Exception("bad request")
    error.status_code = 400
    client.chat.completions.create.side_effect = [error]
    backend = GroqBackend(make_settings(groq_max_retries=3), client=client)

    with pytest.raises(Exception):
        backend.generate(make_request())
    assert client.chat.completions.create.call_count == 1
