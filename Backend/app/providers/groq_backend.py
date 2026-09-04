"""
GroqBackend — the only place in the codebase that imports the Groq SDK.

STATUS (be exact about this, per PROJECT_STATUS.md's "never claim ... API
functionality without evidence"): this module is CODE-PATH-WRITTEN, unit
tested with the real HTTP client mocked out, but NOT LIVE-TESTED against the
actual Groq API in this environment — the sandbox that produced this file has
no network access to Groq. It must be exercised against a real GROQ_API_KEY
before Expo (see tests/test_groq_backend.py and PASS 2 in the audit).

Design constraints this file follows (from PROJECT_STATUS.md):
- bounded retries with exponential backoff; never retry forever
- honor Retry-After on 429 when the provider supplies it; never hammer 429s
- distinguish timeout / connection failure / 5xx (retry) from a genuine
  malformed/empty response (bounded retry, then raise — caller decides on
  a deterministic fallback, this module never fabricates a fallback answer)
- enforce input/output token budgets before sending, per task
- log latency/retry count/token usage where the provider reports it; never
  invent token counts if the provider doesn't return them
- never log the API key
"""
from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime, timezone

from app.config import Settings
from app.providers.llm_backend import (
    GenerationRequest,
    GenerationResult,
    LLMBackend,
    LLMBudgetExceededError,
    LLMMalformedResponseError,
    LLMRateLimitedError,
    LLMTransientError,
)
from app.utils.token_budget import estimate_tokens

logger = logging.getLogger("prepai.groq")

# Errors we treat as transient/retryable vs. terminal. Kept as plain ints
# rather than importing a specific HTTP client's exception hierarchy, so this
# module stays testable without the real `groq` package installed.
RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}


class GroqBackend(LLMBackend):
    def __init__(self, settings: Settings, client=None):
        self._settings = settings
        if not settings.groq_api_key and client is None:
            # We don't raise here — a missing key should surface as a clear
            # error on first *use*, not crash app startup (health checks and
            # non-Groq endpoints must still work).
            logger.warning("GROQ_API_KEY is not set; GroqBackend will fail on first request.")
        self._client = client or self._build_client()

    def _build_client(self):
        try:
            from groq import Groq  # imported lazily so the package is only
        except ImportError as exc:  # required if this backend is actually used
            raise LLMBackendError_import_hint() from exc
        return Groq(api_key=self._settings.groq_api_key, timeout=self._settings.groq_timeout_seconds)

    def generate(self, request: GenerationRequest) -> GenerationResult:
        settings = self._settings
        request_id = str(uuid.uuid4())

        input_tokens_estimate = estimate_tokens(request.system_prompt) + estimate_tokens(request.user_prompt)
        if input_tokens_estimate > settings.groq_max_input_tokens:
            raise LLMBudgetExceededError(
                f"[{request_id}] estimated input tokens {input_tokens_estimate} exceeds "
                f"budget {settings.groq_max_input_tokens} for task={request.task}"
            )

        max_output = min(request.max_output_tokens, settings.groq_max_output_tokens)

        last_error: Exception | None = None
        for attempt in range(1, settings.groq_max_retries + 1):
            ts = datetime.now(timezone.utc).isoformat()
            call_label = "generation" if "gen" in request.task.lower() else "verification"
            logger.info(
                "[GD GROQ] %s call started | purpose=%s | model=%s | max_tokens=%d | timestamp=%s | attempt=%d",
                call_label, request.task, settings.groq_model, max_output, ts, attempt
            )
            start = time.monotonic()
            try:
                response = self._client.chat.completions.create(
                    model=settings.groq_model,
                    messages=[
                        {"role": "system", "content": request.system_prompt},
                        {"role": "user", "content": request.user_prompt},
                    ],
                    max_tokens=max_output,
                    max_completion_tokens=max_output,
                    temperature=0.4,
                )
            except Exception as exc:  # noqa: BLE001 — provider SDK exception types vary
                status_code = getattr(exc, "status_code", None)
                latency = round(time.monotonic() - start, 3)
                last_error = exc
                retry_after = _extract_retry_after(exc)
                rl_headers = _extract_rate_limit_headers(exc)

                logger.warning(
                    "[GD GROQ] %s call failed | purpose=%s | model=%s | timestamp=%s | status=%s | latency=%.3fs | retry_count=%d | retry_after=%s | error_type=%s | error_msg=%r | headers=%s",
                    call_label, request.task, settings.groq_model, ts, status_code, latency, attempt - 1, retry_after, type(exc).__name__, str(exc), rl_headers
                )

                if status_code == 429:
                    logger.info(
                        "groq_rate_limited request_id=%s task=%s attempt=%s retry_after=%s",
                        request_id, request.task, attempt, retry_after,
                    )
                    if attempt == settings.groq_max_retries or (retry_after is not None and retry_after > 10.0):
                        raise LLMRateLimitedError(f"[{request_id}] rate limited after {attempt} attempts (retry_after={retry_after})", retry_after) from exc
                    time.sleep(retry_after if retry_after is not None else _backoff_seconds(attempt))
                    continue

                if status_code in RETRYABLE_STATUS_CODES or status_code is None:
                    logger.info(
                        "groq_transient_error request_id=%s task=%s attempt=%s status=%s latency=%.2f",
                        request_id, request.task, attempt, status_code, latency,
                    )
                    if attempt == settings.groq_max_retries:
                        raise LLMTransientError(f"[{request_id}] transient failure after {attempt} attempts: {exc}") from exc
                    time.sleep(_backoff_seconds(attempt))
                    continue

                # Non-retryable provider error (e.g. 400 bad request) — fail fast.
                raise LLMBackendError_from(exc, request_id) from exc

            latency = round(time.monotonic() - start, 3)
            text = _extract_text(response)
            if not text or not text.strip():
                logger.info(
                    "groq_empty_response request_id=%s task=%s attempt=%s",
                    request_id, request.task, attempt,
                )
                if attempt == settings.groq_max_retries:
                    raise LLMMalformedResponseError(f"[{request_id}] empty response after {attempt} attempts")
                time.sleep(_backoff_seconds(attempt))
                continue

            usage = getattr(response, "usage", None)
            in_tok = getattr(usage, "prompt_tokens", None) if usage else None
            out_tok = getattr(usage, "completion_tokens", None) if usage else None

            logger.info(
                "[GD GROQ] %s call succeeded | purpose=%s | model=%s | timestamp=%s | status=200 | latency=%.3fs | retry_count=%d | in_tok=%s | out_tok=%s",
                call_label, request.task, settings.groq_model, ts, latency, attempt - 1, in_tok, out_tok,
            )

            return GenerationResult(
                text=text.strip(),
                provider="groq",
                model=settings.groq_model,
                input_tokens=in_tok,
                output_tokens=out_tok,
                latency_seconds=round(latency, 3),
                retry_count=attempt - 1,
            )

        # Should be unreachable — every branch above either returns or raises.
        raise LLMTransientError(f"[{request_id}] exhausted retries") from last_error


def _extract_text(response) -> str:
    try:
        return response.choices[0].message.content or ""
    except (AttributeError, IndexError):
        return ""


def _extract_retry_after(exc) -> float | None:
    headers = getattr(exc, "response", None)
    headers = getattr(headers, "headers", None) if headers else None
    value = headers.get("retry-after") or headers.get("Retry-After") if headers else None
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _extract_rate_limit_headers(exc) -> dict[str, str]:
    headers = getattr(exc, "response", None)
    headers = getattr(headers, "headers", None) if headers else None
    if not headers:
        return {}
    rl_headers = {}
    for k, v in headers.items():
        k_lower = k.lower()
        if "ratelimit" in k_lower or k_lower in ("retry-after", "x-request-id"):
            rl_headers[k] = v
    return rl_headers


def _backoff_seconds(attempt: int) -> float:
    # Exponential backoff, capped, with no jitter dependency required.
    return min(8.0, 1.5 * (2 ** (attempt - 1)))


def LLMBackendError_import_hint():
    from app.providers.llm_backend import LLMBackendError
    return LLMBackendError(
        "The 'groq' package is not installed. Run: pip install groq"
    )


def LLMBackendError_from(exc, request_id: str):
    from app.providers.llm_backend import LLMBackendError
    return LLMBackendError(f"[{request_id}] non-retryable Groq error: {exc}")
