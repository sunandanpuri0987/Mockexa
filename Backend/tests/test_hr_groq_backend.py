import json
from unittest.mock import MagicMock
from types import SimpleNamespace

from app.controllers.hr_groq_backend import GroqHRBackend
from app.controllers.hr_controller import HRQuestion
from app.providers.llm_backend import LLMBackendError

def fake_generation_result(text: str):
    return SimpleNamespace(text=text)

def test_hr_groq_backend_success():
    router = MagicMock()
    valid_json = json.dumps({
        "clarity": 0.9, "specificity": 0.8, "ownership": 0.8,
        "communication": 0.9, "teamwork": 0.7, "leadership": 0.6,
        "problem_solving": 0.8, "feedback": "Good job."
    })
    router.generate.return_value = fake_generation_result(valid_json)
    
    backend = GroqHRBackend(model_router=router)
    q = HRQuestion(id="q1", question="Q?", category="C")
    eval_result = backend.evaluate(q, "My answer")
    
    assert eval_result.clarity == 0.9
    assert eval_result.feedback == "Good job."
    assert 0.0 <= eval_result.overall_score <= 1.0
    
    router.generate.assert_called_once()
    assert router.generate.call_args[1]["task"] == "hr_eval"

def test_hr_groq_backend_malformed_json():
    router = MagicMock()
    router.generate.return_value = fake_generation_result("not json")
    
    backend = GroqHRBackend(model_router=router)
    q = HRQuestion(id="q1", question="Q?", category="C")
    
    eval_result = backend.evaluate(q, "My answer")
    assert eval_result.clarity == -1.0
    assert eval_result.feedback == "Evaluation failed."

def test_hr_groq_backend_missing_keys():
    router = MagicMock()
    invalid_json = json.dumps({"clarity": 0.9})
    router.generate.return_value = fake_generation_result(invalid_json)
    
    backend = GroqHRBackend(model_router=router)
    q = HRQuestion(id="q1", question="Q?", category="C")
    
    eval_result = backend.evaluate(q, "My answer")
    assert eval_result.clarity == -1.0
