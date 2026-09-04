"""
ModelRouter — the one and only thing controllers call for generation.

    model_router.generate(task="gd_generation", ...)

Controllers must never import GroqBackend (or any concrete backend) directly.
This keeps Groq SDK usage in exactly one place (groq_backend.py) and makes it
possible to add LocalQwenBackend (the existing GD LoRA adapter, once its live
generation quality is confirmed acceptable for production use — see the
project audit) as a drop-in alternative without touching any controller.

Task -> per-task token budget mapping lives here, not scattered across
callers, per PROJECT_STATUS.md's "prefer separate settings" + "do not
scatter Groq SDK calls throughout the project."
"""
from __future__ import annotations

from app.config import Settings
from app.providers.llm_backend import GenerationRequest, GenerationResult, LLMBackend

_TASK_BUDGETS = {
    "gd_generation": ("gd_generation_max_input_tokens", "gd_generation_max_output_tokens"),
    "gd_verification": ("gd_generation_max_input_tokens", "gd_generation_max_output_tokens"),
    "technical_eval": ("technical_eval_max_input_tokens", "technical_eval_max_output_tokens"),
    "hr_eval": ("hr_eval_max_input_tokens", "hr_eval_max_output_tokens"),
    "feedback": ("feedback_max_input_tokens", "feedback_max_output_tokens"),
}


class ModelRouter:
    def __init__(self, settings: Settings, backends: dict[str, LLMBackend] | LLMBackend):
        self._settings = settings
        if isinstance(backends, dict):
            self._backends = backends
            self._default_backend = None
        else:
            self._backends = {}
            self._default_backend = backends

    def generate(
        self,
        task: str,
        system_prompt: str,
        user_prompt: str,
        json_schema_hint: str | None = None,
    ) -> GenerationResult:
        if task not in _TASK_BUDGETS:
            raise ValueError(f"Unknown task '{task}'. Add it to _TASK_BUDGETS with explicit budgets.")
        _, output_key = _TASK_BUDGETS[task]
        max_output_tokens = getattr(self._settings, output_key)

        request = GenerationRequest(
            task=task,
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            max_output_tokens=max_output_tokens,
            json_schema_hint=json_schema_hint,
        )
        backend = self._backends.get(task, self._default_backend)
        if backend is None:
            raise ValueError(f"No backend configured for task '{task}' and no default backend provided.")
        return backend.generate(request)
