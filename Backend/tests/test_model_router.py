from unittest.mock import MagicMock

import pytest

from app.config import Settings
from app.providers.llm_backend import GenerationResult
from app.providers.model_router import ModelRouter


def make_settings() -> Settings:
    return Settings(
        gd_generation_max_input_tokens=100, gd_generation_max_output_tokens=50,
        technical_eval_max_input_tokens=200, technical_eval_max_output_tokens=60,
        hr_eval_max_input_tokens=200, hr_eval_max_output_tokens=60,
        feedback_max_input_tokens=300, feedback_max_output_tokens=70,
    )


def test_generate_uses_task_specific_output_budget():
    backend = MagicMock()
    backend.generate.return_value = GenerationResult(
        text="ok", provider="groq", model="m", input_tokens=1, output_tokens=1,
        latency_seconds=0.1, retry_count=0,
    )
    router = ModelRouter(make_settings(), backend)

    router.generate(task="gd_generation", system_prompt="s", user_prompt="u")

    sent_request = backend.generate.call_args[0][0]
    assert sent_request.max_output_tokens == 50
    assert sent_request.task == "gd_generation"


def test_generate_rejects_unknown_task():
    backend = MagicMock()
    router = ModelRouter(make_settings(), backend)
    with pytest.raises(ValueError):
        router.generate(task="not_a_real_task", system_prompt="s", user_prompt="u")
