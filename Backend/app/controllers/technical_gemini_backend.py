"""
GeminiTechnicalBackend — implements the same `evaluate`/`follow_up` interface
as CuratedTechnicalBackend (technical_controller.LLMBackend Protocol), using
Gemini for deep candidate answer evaluation.

Evaluates correctness, completeness, relevance, and reasoning, returning
an AnswerAnalysis with candidate-facing constructive feedback and identified
missing concepts or misconceptions.
"""
from __future__ import annotations

import json
import logging
import re
from typing import Any

from app.controllers.technical_controller import AnswerAnalysis, FollowUpDecision, Question
from app.providers.llm_backend import LLMBackendError
from app.providers.model_router import ModelRouter

logger = logging.getLogger("mockexa.technical_gemini_backend")

_VALID_CLASSIFICATIONS = {
    "CORRECT", "MOSTLY_CORRECT", "PARTIALLY_CORRECT", "INCORRECT",
    "IRRELEVANT", "UNCLEAR", "INSUFFICIENT_EVIDENCE", "MISCONCEPTION",
}

_SYSTEM_PROMPT = (
    "You are an expert, objective technical interview evaluator. Given a question, its "
    "expected concepts, ideal reference answer, and a candidate's answer, thoroughly analyze "
    "the candidate's actual response and output ONLY a valid JSON object with exactly these fields:\n"
    '{\n'
    '  "classification": "CORRECT" | "MOSTLY_CORRECT" | "PARTIALLY_CORRECT" | "INCORRECT" | "MISCONCEPTION" | "UNCLEAR" | "IRRELEVANT" | "INSUFFICIENT_EVIDENCE",\n'
    '  "correctness": float between 0.0 and 1.0 (accuracy of technical claims),\n'
    '  "completeness": float between 0.0 and 1.0 (coverage of expected concepts),\n'
    '  "relevance": float between 0.0 and 1.0 (degree to which response addresses question),\n'
    '  "reasoning_score": float between 0.0 and 1.0 (depth of technical justification and complexity analysis),\n'
    '  "feedback": "Concise 1-2 sentence constructive critique explaining what the candidate answered well and exactly what was missing or incorrect.",\n'
    '  "missing_concepts": ["concept 1", ...],\n'
    '  "misconceptions": ["misconception 1", ...]\n'
    '}\n'
    "Strict evaluation guidelines:\n"
    "1. Base your evaluation strictly on the candidate's actual words.\n"
    "2. If the candidate provides a correct, detailed explanation (even if phrased in their own words), reward high correctness (0.85-1.0) and completeness.\n"
    "3. If the answer is off-topic, nonsensical, or displays major factual errors, classify accurately as INCORRECT or MISCONCEPTION.\n"
    "4. Output raw JSON ONLY without any markdown code fences or surrounding text."
)


def _parse_score(value: Any, default: float = 0.0) -> float:
    if value is None:
        return default
    try:
        score = float(value)
    except (ValueError, TypeError):
        return default

    # Handle 1-5 scale (common in some LLM outputs)
    if 1.0 < score <= 5.0:
        score = score / 5.0
    # Handle 0-100 percentage scale
    elif score > 5.0:
        score = min(1.0, score / 100.0)

    return max(0.0, min(1.0, score))


def _normalize_classification(raw: Any, correctness: float) -> str:
    cleaned = str(raw or "").strip().upper().replace(" ", "_").replace("-", "_")
    if cleaned in _VALID_CLASSIFICATIONS:
        return cleaned

    # Fuzzy matches
    if "MISCONCEPT" in cleaned:
        return "MISCONCEPTION"
    if "MOSTLY" in cleaned:
        return "MOSTLY_CORRECT"
    if "PARTIAL" in cleaned:
        return "PARTIALLY_CORRECT"
    if "CORRECT" in cleaned:
        return "CORRECT"
    if "IRRELEVANT" in cleaned:
        return "IRRELEVANT"
    if "UNCLEAR" in cleaned:
        return "UNCLEAR"
    if "INSUFFICIENT" in cleaned:
        return "INSUFFICIENT_EVIDENCE"

    if correctness >= 0.80:
        return "CORRECT"
    if correctness >= 0.55:
        return "MOSTLY_CORRECT"
    if correctness >= 0.30:
        return "PARTIALLY_CORRECT"
    return "INCORRECT"


class GeminiTechnicalBackend:
    def __init__(self, model_router: ModelRouter):
        self._router = model_router

    def evaluate(self, question: Question, answer: str) -> AnswerAnalysis:
        user_prompt = (
            f"QUESTION: {question.question}\n"
            f"DOMAIN: {question.domain} - {question.subtopic}\n"
            f"EXPECTED CONCEPTS: {', '.join(question.expected_concepts)}\n"
            f"IDEAL REFERENCE ANSWER (do not reveal directly): {question.ideal_answer}\n\n"
            f"CANDIDATE ANSWER TO EVALUATE:\n{answer}"
        )
        try:
            result = self._router.generate(
                task="technical_eval",
                system_prompt=_SYSTEM_PROMPT,
                user_prompt=user_prompt,
            )
            raw_text = result.text.strip()
            # Strip markdown fences if present
            if raw_text.startswith("```"):
                raw_text = re.sub(r"^```(?:json)?\s*", "", raw_text)
                raw_text = re.sub(r"\s*```$", "", raw_text)
                raw_text = raw_text.strip()

            parsed = json.loads(raw_text)

            correctness = _parse_score(parsed.get("correctness"), default=0.0)
            completeness = _parse_score(parsed.get("completeness"), default=0.0)
            relevance = _parse_score(parsed.get("relevance"), default=0.8)

            # Accept reasoning_score, or numeric reasoning, or fallback based on correctness
            reasoning_val = parsed.get("reasoning_score")
            if reasoning_val is None:
                reasoning_val = parsed.get("reasoning")
            reasoning = _parse_score(reasoning_val, default=max(0.2, (correctness + completeness) / 2.0))

            # Extract feedback
            feedback = ""
            if isinstance(parsed.get("feedback"), str) and parsed["feedback"].strip():
                feedback = parsed["feedback"].strip()
            elif isinstance(parsed.get("reasoning"), str) and parsed["reasoning"].strip() and not parsed["reasoning"].strip().replace(".", "", 1).isdigit():
                feedback = parsed["reasoning"].strip()

            classification = _normalize_classification(parsed.get("classification"), correctness)

            missing_raw = parsed.get("missing_concepts") or []
            if isinstance(missing_raw, list):
                missing_concepts = tuple(str(c) for c in missing_raw if str(c).strip())
            else:
                missing_concepts = ()

            misconceptions_raw = parsed.get("misconceptions") or []
            if isinstance(misconceptions_raw, list):
                misconceptions = tuple(str(m) for m in misconceptions_raw if str(m).strip())
            else:
                misconceptions = ()

            overall = round(
                0.45 * correctness + 0.25 * completeness + 0.15 * reasoning + 0.15 * relevance,
                2,
            )

            if not feedback:
                if classification == "CORRECT":
                    feedback = "Excellent response covering the expected technical concepts and reasoning."
                elif classification == "MOSTLY_CORRECT":
                    feedback = f"Good technical explanation. To improve, touch upon {', '.join(missing_concepts[:2]) if missing_concepts else 'further trade-offs'}."
                elif classification == "PARTIALLY_CORRECT":
                    feedback = f"Partially correct answer, but missed key concepts: {', '.join(missing_concepts[:3]) if missing_concepts else 'core details'}."
                else:
                    feedback = f"Answer did not satisfy the question requirements. Review {question.subtopic} concepts."

            return AnswerAnalysis(
                classification=classification,
                correctness=round(correctness, 2),
                completeness=round(completeness, 2),
                relevance=round(relevance, 2),
                reasoning=round(reasoning, 2),
                missing_concepts=missing_concepts,
                misconceptions=misconceptions,
                overall_score=overall,
                feedback=feedback,
            )
        except (LLMBackendError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
            logger.warning("gemini_technical_eval_failed reason=%s", exc)
            return AnswerAnalysis(
                classification="INSUFFICIENT_EVIDENCE",
                correctness=-1.0,  # deliberately out of [0,1] so valid_analysis() rejects it
                completeness=0.0, relevance=0.0, reasoning=0.0,
                missing_concepts=(), misconceptions=(), overall_score=0.0,
                feedback="",
            )

    def follow_up(self, question: Question, decision: FollowUpDecision) -> Question:
        from app.controllers.technical_controller import CuratedTechnicalBackend
        return CuratedTechnicalBackend().follow_up(question, decision)
