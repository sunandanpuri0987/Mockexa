"""
GroqTechnicalBackend — implements the same `evaluate`/`follow_up` interface
as CuratedTechnicalBackend (technical_controller.LLMBackend Protocol), but
asks Groq to do the evaluation instead of the rubric heuristic.

Per PROJECT_STATUS.md: Groq may evaluate correctness/completeness/relevance/
reasoning, but InterviewController remains authoritative for question
selection, difficulty, follow-up policy, and stopping — this class only ever
returns an AnswerAnalysis/Question; it never touches InterviewState.

Malformed or unparseable Groq output must never mutate state. This class
raises nothing on malformed output — InterviewController.submit_answer()
already checks `output_validator.valid_analysis(...)` and falls back to
CuratedTechnicalBackend if validation fails, so this backend simply returns
a best-effort AnswerAnalysis and lets that existing safety net catch it.

STATUS: written and unit-tested with Groq mocked out (see
tests/test_technical_groq_backend.py). Not yet exercised against the live
Groq API — see the model artifact / Groq audit notes.
"""
from __future__ import annotations

import json
import logging

from app.controllers.technical_controller import AnswerAnalysis, FollowUpDecision, Question
from app.providers.llm_backend import LLMBackendError
from app.providers.model_router import ModelRouter

logger = logging.getLogger("prepai.technical_groq_backend")

_VALID_CLASSIFICATIONS = {
    "CORRECT", "MOSTLY_CORRECT", "PARTIALLY_CORRECT", "INCORRECT",
    "IRRELEVANT", "UNCLEAR", "INSUFFICIENT_EVIDENCE", "MISCONCEPTION",
}

_SYSTEM_PROMPT = (
    "You are a strict technical interview evaluator. Given a question, its "
    "expected concepts, and a candidate's answer, output ONLY a JSON object "
    "with exactly these fields and no others:\n"
    '{"classification": one of ' + json.dumps(sorted(_VALID_CLASSIFICATIONS)) + ", "
    '"correctness": float 0-1, "completeness": float 0-1, "relevance": float 0-1, '
    '"reasoning": float 0-1, "missing_concepts": [string, ...], "misconceptions": [string, ...]}\n'
    "Do not include any explanation, markdown, or text outside the JSON object. "
    "Do not reveal your reasoning process, only the final JSON."
)


class GroqTechnicalBackend:
    def __init__(self, model_router: ModelRouter):
        self._router = model_router

    def evaluate(self, question: Question, answer: str) -> AnswerAnalysis:
        user_prompt = (
            f"QUESTION: {question.question}\n"
            f"EXPECTED CONCEPTS: {', '.join(question.expected_concepts)}\n"
            f"IDEAL ANSWER (reference, do not reveal to candidate): {question.ideal_answer}\n"
            f"CANDIDATE ANSWER: {answer}"
        )
        try:
            result = self._router.generate(
                task="technical_eval",
                system_prompt=_SYSTEM_PROMPT,
                user_prompt=user_prompt,
            )
            parsed = json.loads(result.text)
            classification = parsed["classification"]
            if classification not in _VALID_CLASSIFICATIONS:
                raise ValueError(f"unknown classification: {classification}")
            overall = round(
                0.45 * float(parsed["correctness"]) + 0.25 * float(parsed["completeness"])
                + 0.20 * float(parsed["reasoning"]) + 0.10 * float(parsed["relevance"]),
                3,
            )
            return AnswerAnalysis(
                classification=classification,
                correctness=float(parsed["correctness"]),
                completeness=float(parsed["completeness"]),
                relevance=float(parsed["relevance"]),
                reasoning=float(parsed["reasoning"]),
                missing_concepts=tuple(parsed.get("missing_concepts", [])),
                misconceptions=tuple(parsed.get("misconceptions", [])),
                overall_score=overall,
            )
        except (LLMBackendError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
            # Deliberately swallowed here: InterviewController's own
            # StructuredOutputValidator + CuratedTechnicalBackend fallback is
            # the safety net for this. We log and return a value that will
            # fail validation cleanly rather than raising into the controller.
            logger.warning("groq_technical_eval_failed reason=%s", exc)
            return AnswerAnalysis(
                classification="INSUFFICIENT_EVIDENCE",
                correctness=-1.0,  # deliberately out of [0,1] so valid_analysis() rejects it
                completeness=0.0, relevance=0.0, reasoning=0.0,
                missing_concepts=(), misconceptions=(), overall_score=0.0,
            )

    def follow_up(self, question: Question, decision: FollowUpDecision) -> Question:
        # Follow-up question *generation* via Groq is deliberately not
        # implemented yet — QuestionValidator requires it to pass the same
        # novelty/schema checks as curated questions, and getting that
        # reliable needs its own test pass. CuratedTechnicalBackend.follow_up
        # already produces a validator-passing follow-up, so route there for
        # now rather than shipping an unverified follow-up generator.
        from app.controllers.technical_controller import CuratedTechnicalBackend
        return CuratedTechnicalBackend().follow_up(question, decision)
