import json
from unittest.mock import MagicMock
from types import SimpleNamespace

from app.controllers.hr_gemini_backend import GeminiHRBackend
from app.controllers.hr_controller import CuratedHRBackend, HRQuestion
from app.providers.llm_backend import LLMBackendError

def fake_generation_result(text: str):
    return SimpleNamespace(text=text)

def test_hr_gemini_backend_success():
    router = MagicMock()
    valid_json = json.dumps({
        "clarity": 0.9, "specificity": 0.8, "ownership": 0.8,
        "communication": 0.9, "teamwork": 0.7, "leadership": 0.6,
        "problem_solving": 0.8, "feedback": "Good job."
    })
    router.generate.return_value = fake_generation_result(valid_json)
    
    backend = GeminiHRBackend(model_router=router)
    q = HRQuestion(id="q1", question="Q?", category="C")
    eval_result = backend.evaluate(q, "My answer")
    
    assert eval_result.clarity == 0.9
    assert eval_result.feedback == "Good job."
    assert 0.0 <= eval_result.overall_score <= 1.0
    
    router.generate.assert_called_once()
    assert router.generate.call_args[1]["task"] == "hr_eval"

def test_hr_gemini_backend_malformed_json():
    router = MagicMock()
    router.generate.return_value = fake_generation_result("not json")
    
    backend = GeminiHRBackend(model_router=router)
    q = HRQuestion(id="q1", question="Q?", category="C")
    
    eval_result = backend.evaluate(q, "My answer")
    assert eval_result.clarity == 0.0
    assert eval_result.feedback == "Evaluation failed."

def test_hr_gemini_backend_missing_keys():
    router = MagicMock()
    invalid_json = json.dumps({"clarity": 0.9})
    router.generate.return_value = fake_generation_result(invalid_json)
    
    backend = GeminiHRBackend(model_router=router)
    q = HRQuestion(id="q1", question="Q?", category="C")
    
    eval_result = backend.evaluate(q, "My answer")
    assert eval_result.clarity == 0.0


def test_hr_gemini_backend_returns_contextual_follow_up():
    router = MagicMock()
    router.generate.return_value = fake_generation_result(json.dumps({
        "clarity": 0.8, "specificity": 0.42, "ownership": 0.35,
        "communication": 0.75, "teamwork": 0.6, "leadership": 0.5,
        "problem_solving": 0.55, "feedback": "Ownership was unclear.",
        "needs_follow_up": True,
        "follow_up_question": "You said the team missed the deadline; what decision did you personally make that contributed to it?",
        "follow_up_category": "Accountability probe",
        "probe_focus": "ownership",
        "pressure_level": 2,
        "observed_signal": "Candidate used team-level language and did not identify a personal decision."
    }))
    backend = GeminiHRBackend(model_router=router)
    earlier_q = HRQuestion(id="earlier", question="Tell me about yourself.", category="Introduction")
    earlier_eval = backend.evaluate(earlier_q, "I led a migration.")
    current_q = HRQuestion(id="failure", question="Tell me about a failure.", category="Failure")

    result = backend.evaluate_with_context(
        current_q,
        "The team missed the deadline.",
        ((earlier_q, "I led a migration.", earlier_eval),),
    )

    assert result.needs_follow_up is True
    assert result.probe_focus == "ownership"
    assert result.pressure_level == 2
    assert "personally" in result.follow_up_question
    assert "RECENT INTERVIEW CONTEXT" in router.generate.call_args.kwargs["user_prompt"]


def test_hr_gemini_prompt_receives_selected_style():
    router = MagicMock()
    router.generate.return_value = fake_generation_result(json.dumps({
        "clarity": 0.8, "specificity": 0.8, "ownership": 0.8,
        "communication": 0.8, "teamwork": 0.8, "leadership": 0.8,
        "problem_solving": 0.8, "feedback": "Relevant evidence."
    }))
    backend = GeminiHRBackend(model_router=router)
    question = HRQuestion("q", "How would you handle two conflicting stakeholders?", "Judgment", "Stress Interview")
    backend.evaluate(question, "I would clarify priorities, document the risk, and own the decision.")
    assert "INTERVIEW STYLE: Stress Interview" in router.generate.call_args.kwargs["user_prompt"]


def test_irrelevant_answer_is_rejected_before_calling_gemini():
    router = MagicMock()
    backend = GeminiHRBackend(model_router=router, fallback=CuratedHRBackend())
    question = HRQuestion("q", "Tell me about a conflict you resolved.", "Conflict", "Behavioral")
    result = backend.evaluate(question, "random blue banana cricket whatever")
    assert result.overall_score < 0.20
    assert result.needs_follow_up is True
    router.generate.assert_not_called()
