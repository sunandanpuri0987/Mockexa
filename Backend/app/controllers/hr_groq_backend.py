from __future__ import annotations

import json
import logging

from app.controllers.hr_controller import HREvaluation, HRQuestion
from app.providers.llm_backend import LLMBackendError
from app.providers.model_router import ModelRouter

logger = logging.getLogger("prepai.hr_groq_backend")


_SYSTEM_PROMPT = (
    "You are a strict HR interview evaluator assessing a candidate's behavioral responses. "
    "Given a question and a candidate's answer, evaluate the answer strictly on the following dimensions. "
    "Output ONLY a JSON object with exactly these fields and no others:\n"
    '{"clarity": float 0-1, "specificity": float 0-1, "ownership": float 0-1, '
    '"communication": float 0-1, "teamwork": float 0-1, "leadership": float 0-1, '
    '"problem_solving": float 0-1, "feedback": string}\n'
    "The feedback string should be a concise 1-2 sentence constructive critique of the answer. "
    "Do not include any explanation, markdown, or text outside the JSON object. "
    "Do not reveal your reasoning process, only the final JSON."
)


class GroqHRBackend:
    def __init__(self, model_router: ModelRouter):
        self._router = model_router

    def evaluate(self, question: HRQuestion, answer: str) -> HREvaluation:
        user_prompt = (
            f"QUESTION CATEGORY: {question.category}\n"
            f"QUESTION: {question.question}\n"
            f"CANDIDATE ANSWER: {answer}"
        )
        try:
            result = self._router.generate(
                task="hr_eval",
                system_prompt=_SYSTEM_PROMPT,
                user_prompt=user_prompt,
            )
            parsed = json.loads(result.text)
            
            clarity = float(parsed["clarity"])
            specificity = float(parsed["specificity"])
            ownership = float(parsed["ownership"])
            communication = float(parsed["communication"])
            teamwork = float(parsed["teamwork"])
            leadership = float(parsed["leadership"])
            problem_solving = float(parsed["problem_solving"])
            
            overall = round(
                (clarity + specificity + ownership + communication + teamwork + leadership + problem_solving) / 7.0,
                3,
            )
            return HREvaluation(
                clarity=clarity,
                specificity=specificity,
                ownership=ownership,
                communication=communication,
                teamwork=teamwork,
                leadership=leadership,
                problem_solving=problem_solving,
                feedback=str(parsed.get("feedback", "No feedback provided.")),
                overall_score=overall,
            )
        except (LLMBackendError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
            logger.warning("groq_hr_eval_failed reason=%s", exc)
            return HREvaluation(
                clarity=-1.0,  # deliberately out of [0,1]
                specificity=0.0, ownership=0.0, communication=0.0,
                teamwork=0.0, leadership=0.0, problem_solving=0.0,
                feedback="Evaluation failed.", overall_score=0.0,
            )
