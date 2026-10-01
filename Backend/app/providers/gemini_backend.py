"""Google Gemini implementation of the shared LLM backend protocol."""
from __future__ import annotations

import logging
import time
import uuid

import httpx

from app.config import Settings
from app.providers.llm_backend import (
    GenerationRequest,
    GenerationResult,
    LLMBackend,
    LLMBackendError,
    LLMBudgetExceededError,
    LLMMalformedResponseError,
    LLMRateLimitedError,
    LLMTransientError,
)
from app.utils.token_budget import estimate_tokens

logger = logging.getLogger("mockexa.gemini")
RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}


class GeminiBackend(LLMBackend):
    """Synchronous Gemini generateContent client with bounded retries."""

    def __init__(self, settings: Settings, client: httpx.Client | None = None):
        self._settings = settings
        self._client = client or httpx.Client(timeout=settings.gemini_timeout_seconds)

    def generate(self, request: GenerationRequest) -> GenerationResult:
        settings = self._settings
        request_id = str(uuid.uuid4())
        if not settings.gemini_api_key:
            raise LLMBackendError("GEMINI_API_KEY is not configured")

        input_estimate = estimate_tokens(request.system_prompt) + estimate_tokens(request.user_prompt)
        if input_estimate > settings.gemini_max_input_tokens:
            raise LLMBudgetExceededError(
                f"[{request_id}] estimated input tokens {input_estimate} exceeds "
                f"budget {settings.gemini_max_input_tokens} for task={request.task}"
            )

        max_output = min(request.max_output_tokens, settings.gemini_max_output_tokens)
        generation_config: dict[str, object] = {
            "temperature": 0.4,
            "maxOutputTokens": max_output,
        }
        if request.json_schema_hint or request.task in {
            "gd_verification",
            "technical_eval",
            "hr_eval",
            "feedback",
        }:
            generation_config["responseMimeType"] = "application/json"

        payload = {
            "systemInstruction": {"parts": [{"text": request.system_prompt}]},
            "contents": [{"role": "user", "parts": [{"text": request.user_prompt}]}],
            "generationConfig": generation_config,
        }
        active_model = settings.gemini_model
        fallback_model = settings.gemini_fallback_model
        used_fallback = False

        last_error: Exception | None = None
        total_attempts = max(settings.gemini_max_retries, 2 if fallback_model else 1)
        attempt = 0
        while attempt < total_attempts:
            attempt += 1
            started = time.monotonic()
            url = (
                "https://generativelanguage.googleapis.com/v1beta/models/"
                f"{active_model}:generateContent"
            )
            try:
                response = self._client.post(
                    url,
                    headers={
                        "x-goog-api-key": settings.gemini_api_key,
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
                if response.status_code >= 400:
                    raise _GeminiHTTPError(response)
                data = response.json()
            except Exception as exc:  # HTTP and test doubles expose different errors
                last_error = exc
                status_code = getattr(exc, "status_code", None)
                retry_after = _retry_after(exc)
                logger.warning(
                    "gemini_call_failed request_id=%s task=%s model=%s status=%s "
                    "latency=%.3f attempt=%d",
                    request_id, request.task, active_model, status_code,
                    time.monotonic() - started, attempt,
                )
                if status_code == 429:
                    if fallback_model and fallback_model != active_model and not used_fallback:
                        logger.warning(
                            "gemini_model_fallback request_id=%s task=%s from_model=%s to_model=%s",
                            request_id, request.task, active_model, fallback_model,
                        )
                        active_model = fallback_model
                        used_fallback = True
                        total_attempts = max(total_attempts, attempt + 1)
                        continue
                    if attempt >= total_attempts or (retry_after or 0) > 10:
                        raise LLMRateLimitedError(
                            f"[{request_id}] Gemini rate limited after {attempt} attempts",
                            retry_after,
                        ) from exc
                    time.sleep(retry_after if retry_after is not None else _backoff(attempt))
                    continue
                if status_code in RETRYABLE_STATUS_CODES or status_code is None:
                    if attempt >= total_attempts:
                        raise LLMTransientError(
                            f"[{request_id}] Gemini transient failure after {attempt} attempts: {exc}"
                        ) from exc
                    time.sleep(_backoff(attempt))
                    continue
                raise LLMBackendError(
                    f"[{request_id}] non-retryable Gemini error (HTTP {status_code})"
                ) from exc

            text = _extract_text(data)
            if not text.strip():
                if attempt == settings.gemini_max_retries:
                    raise LLMMalformedResponseError(
                        f"[{request_id}] empty Gemini response after {attempt} attempts"
                    )
                time.sleep(_backoff(attempt))
                continue

            usage = data.get("usageMetadata") or {}
            latency = round(time.monotonic() - started, 3)
            logger.info(
                "gemini_call_succeeded request_id=%s task=%s model=%s latency=%.3f retries=%d",
                request_id, request.task, active_model, latency, attempt - 1,
            )
            return GenerationResult(
                text=text.strip(),
                provider="gemini",
                model=active_model,
                input_tokens=usage.get("promptTokenCount"),
                output_tokens=usage.get("candidatesTokenCount"),
                latency_seconds=latency,
                retry_count=attempt - 1,
            )

        raise LLMTransientError(f"[{request_id}] exhausted Gemini retries") from last_error


class _GeminiHTTPError(Exception):
    def __init__(self, response):
        self.status_code = response.status_code
        self.response = response
        super().__init__(f"Gemini HTTP {response.status_code}")


def _extract_text(data: dict) -> str:
    try:
        parts = data["candidates"][0]["content"]["parts"]
        return "".join(str(part.get("text", "")) for part in parts)
    except (KeyError, IndexError, TypeError):
        return ""


def _retry_after(exc: Exception) -> float | None:
    response = getattr(exc, "response", None)
    headers = getattr(response, "headers", None)
    raw = headers.get("retry-after") if headers else None
    try:
        return float(raw) if raw is not None else None
    except (TypeError, ValueError):
        return None


def _backoff(attempt: int) -> float:
    return min(8.0, 1.5 * (2 ** (attempt - 1)))
