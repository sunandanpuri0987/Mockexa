from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Protocol

logger = logging.getLogger("prepai.hr_controller")


@dataclass(frozen=True)
class HRQuestion:
    id: str
    question: str
    category: str


@dataclass(frozen=True)
class HREvaluation:
    clarity: float
    specificity: float
    ownership: float
    communication: float
    teamwork: float
    leadership: float
    problem_solving: float
    feedback: str
    overall_score: float


class HRBackend(Protocol):
    def evaluate(self, question: HRQuestion, answer: str) -> HREvaluation: ...


# Curated question bank based on the STAR method
_HR_QUESTION_BANK = [
    HRQuestion(
        id="hr-intro",
        question="Please introduce yourself and briefly describe your professional background and current role.",
        category="Introduction",
    ),
    HRQuestion(
        id="hr-conflict",
        question="Tell me about a time you had a conflict or disagreement with a team member. How did you handle it?",
        category="Conflict handling",
    ),
    HRQuestion(
        id="hr-leadership",
        question="Describe a situation where you took the initiative to lead a project or resolve an issue outside your strict responsibilities.",
        category="Leadership",
    ),
    HRQuestion(
        id="hr-teamwork",
        question="Tell me about a time you had to collaborate closely with someone whose working style was very different from yours.",
        category="Teamwork",
    ),
    HRQuestion(
        id="hr-problem",
        question="Describe a complex problem or challenging situation you had to solve recently. How did you approach it and what was the result?",
        category="Problem solving",
    ),
]


class HRController:
    """
    Deterministic, authoritative state machine for HR interviews.
    """
    def __init__(self, backend: HRBackend):
        self._backend = backend
        self.max_questions = len(_HR_QUESTION_BANK)
        self.current_index = 0
        self.history: list[tuple[HRQuestion, str, HREvaluation]] = []
        self._started = False
        self._finished = False

    @classmethod
    def from_history(
        cls,
        max_questions: int,
        history: list[dict],
        backend: HRBackend | None = None
    ) -> HRController:
        controller = cls(backend)
        controller.start(max_questions)
        for answer_row in history:
            evaluation_data = answer_row.get("evaluation") or {}
            question_id = evaluation_data.get("question_id") or answer_row.get("question_id")
            question = next((q for q in _HR_QUESTION_BANK if q.id == question_id), None)
            if not question:
                continue

            evaluation_data = answer_row.get("evaluation") or {}
            evaluation = HREvaluation(
                clarity=float(evaluation_data.get("clarity", 0.0)),
                specificity=float(evaluation_data.get("specificity", 0.0)),
                ownership=float(evaluation_data.get("ownership", 0.0)),
                communication=float(evaluation_data.get("communication", 0.0)),
                teamwork=float(evaluation_data.get("teamwork", 0.0)),
                leadership=float(evaluation_data.get("leadership", 0.0)),
                problem_solving=float(evaluation_data.get("problem_solving", 0.0)),
                feedback=evaluation_data.get("feedback", ""),
                overall_score=float(evaluation_data.get("overall_score", 0.0)),
            )
            answer_content = answer_row.get("content", "")
            controller.history.append((question, answer_content, evaluation))
            controller.current_index += 1
            if controller.current_index >= controller.max_questions:
                controller._finished = True
        return controller

    def start(self, max_questions: int = 5) -> HRQuestion:
        if self._started:
            raise ValueError("HR session already started.")
        self.max_questions = min(max_questions, len(_HR_QUESTION_BANK))
        self._started = True
        return _HR_QUESTION_BANK[0]

    def get_next_question(self) -> HRQuestion | None:
        if not self._started:
            return None
        if self.current_index >= self.max_questions:
            return None
        return _HR_QUESTION_BANK[self.current_index]

    def submit_answer(self, answer: str) -> tuple[HREvaluation, HRQuestion | None]:
        if not self._started:
            raise RuntimeError("Cannot submit answer before starting.")
        if self._finished or self.current_index >= self.max_questions:
            raise RuntimeError("Interview is already complete.")

        question = _HR_QUESTION_BANK[self.current_index]
        evaluation = self._backend.evaluate(question, answer)
        
        self.history.append((question, answer, evaluation))
        self.current_index += 1
        
        if self.current_index >= self.max_questions:
            self._finished = True
        
        next_q = self.get_next_question()
        return evaluation, next_q

    def report(self) -> dict:
        if not self._started:
            raise ValueError("Cannot generate report: interview not started.")
        if not self._finished and self.current_index < self.max_questions:
            raise ValueError("Cannot generate report: interview not completed.")
        
        if not self.history:
            return {"overall_score": 0.0, "summary": "No questions answered."}
        
        avg_score = sum(ev.overall_score for _, _, ev in self.history) / len(self.history)
        
        metrics = {
            "clarity": sum(ev.clarity for _, _, ev in self.history) / len(self.history),
            "specificity": sum(ev.specificity for _, _, ev in self.history) / len(self.history),
            "ownership": sum(ev.ownership for _, _, ev in self.history) / len(self.history),
            "communication": sum(ev.communication for _, _, ev in self.history) / len(self.history),
            "teamwork": sum(ev.teamwork for _, _, ev in self.history) / len(self.history),
            "leadership": sum(ev.leadership for _, _, ev in self.history) / len(self.history),
            "problem_solving": sum(ev.problem_solving for _, _, ev in self.history) / len(self.history),
        }
        
        sorted_metrics = sorted(metrics.items(), key=lambda x: x[1])
        strengths = [k for k, v in sorted_metrics[-2:]]
        weaknesses = [k for k, v in sorted_metrics[:2]]
        
        return {
            "overall_score": round(avg_score, 3),
            "questions_answered": len(self.history),
            "metrics": {k: round(v, 3) for k, v in metrics.items()},
            "strengths": strengths,
            "weaknesses": weaknesses,
            "feedback_summary": [
                {
                    "question_id": q.id,
                    "category": q.category,
                    "score": round(ev.overall_score, 3),
                    "feedback": ev.feedback
                } for q, _, ev in self.history
            ]
        }
