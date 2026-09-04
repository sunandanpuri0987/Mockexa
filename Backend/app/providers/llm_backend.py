"""
Provider abstraction. Controllers never talk to Groq (or any provider) SDK
directly — they call `ModelRouter.generate(...)`, which delegates to a
concrete `LLMBackend`.

This intentionally mirrors the `LLMBackend` Protocol already present and
tested in the existing Technical Interview notebook (evaluate/follow_up),
generalized here into a single `generate` entrypoint so GD, Technical, HR,
and feedback can all share one abstraction instead of four bespoke ones.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class LLMBackendError(Exception):
    """Base class for all provider-abstraction failures."""


class LLMRateLimitedError(LLMBackendError):
    """Provider returned 429. `retry_after_seconds` is set when the provider supplied one."""

    def __init__(self, message: str, retry_after_seconds: float | None = None):
        super().__init__(message)
        self.retry_after_seconds = retry_after_seconds


class LLMTransientError(LLMBackendError):
    """5xx / timeout / connection failure — safe to retry with backoff."""


class LLMMalformedResponseError(LLMBackendError):
    """Provider returned an empty or schema-invalid response after retries/fallback."""


class LLMBudgetExceededError(LLMBackendError):
    """Estimated input tokens exceed the task's configured budget before any request was sent."""


@dataclass(frozen=True)
class GenerationRequest:
    task: str  # e.g. "gd_generation", "technical_eval", "hr_eval", "feedback"
    system_prompt: str
    user_prompt: str
    max_output_tokens: int
    # Structured output support: if set, the backend should request/validate JSON
    # matching this schema and raise LLMMalformedResponseError if it can't.
    json_schema_hint: str | None = None


@dataclass(frozen=True)
class GenerationResult:
    text: str
    provider: str
    model: str
    input_tokens: int | None  # None if the provider didn't report usage — never invented
    output_tokens: int | None
    latency_seconds: float
    retry_count: int


class LLMBackend(Protocol):
    def generate(self, request: GenerationRequest) -> GenerationResult: ...
