from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
import random
import re

from app.controllers.technical_controller import (
    AnswerAnalysis,
    Question,
    StructuredOutputValidator,
)
from app.data.company_questions import CompanyQuestion


_STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "how",
    "i", "in", "is", "it", "of", "on", "or", "that", "the", "then", "this",
    "to", "was", "what", "when", "with", "would", "you", "your",
}

_CATEGORY_SIGNALS = {
    "DSA": {
        "algorithm", "array", "binary", "complexity", "data", "dp", "graph", "hash",
        "heap", "iterate", "list", "map", "node", "pointer", "queue", "recursion",
        "space", "stack", "time", "tree", "window",
    },
    "Technical": {
        "api", "class", "code", "concurrency", "database", "debug", "edge", "error",
        "implementation", "lock", "memory", "object", "performance", "test", "thread",
        "tradeoff", "validation",
    },
    "System Design": {
        "api", "availability", "cache", "consistency", "database", "failure", "latency",
        "load", "monitoring", "partition", "queue", "replication", "retry", "scalability",
        "security", "service", "storage", "throughput",
    },
    "Behavioral": {
        "action", "challenge", "customer", "feedback", "impact", "learned", "ownership",
        "result", "situation", "team", "task", "took", "worked",
    },
}


def _tokens(text: str) -> set[str]:
    return {
        token[:-1] if len(token) > 5 and token.endswith("s") else token
        for token in re.findall(r"[a-z0-9]+", text.casefold())
        if token not in _STOPWORDS
    }


def _concept_tokens(concept: str) -> set[str]:
    return _tokens(concept)


def evaluate_company_fast(question: CompanyQuestion, answer: str) -> AnswerAnalysis:
    """Low-latency evidence scorer for interactive company practice.

    This deliberately avoids pretending to be a full semantic judge. It scores
    observable interview evidence: relevant vocabulary, expected concept
    coverage, answer development, reasoning, examples/metrics, and category-
    specific structure. Gemini remains available as the opt-in deep evaluator.
    """
    words = re.findall(r"[a-z0-9]+", answer.casefold())
    tokens = _tokens(answer)
    if len(words) < 3 or not tokens:
        return AnswerAnalysis(
            "INSUFFICIENT_EVIDENCE", 0.0, 0.0, 0.0, 0.0,
            question.focus_points, (), 0.0,
        )

    concept_sets = [_concept_tokens(concept) for concept in question.focus_points]
    concept_hits = [
        concept for concept, terms in zip(question.focus_points, concept_sets)
        if terms and (len(tokens & terms) / len(terms) >= 0.34 or len(tokens & terms) >= 2)
    ]
    missing = tuple(concept for concept in question.focus_points if concept not in concept_hits)
    concept_coverage = len(concept_hits) / max(1, len(question.focus_points))

    question_terms = _tokens(question.prompt) | set().union(*concept_sets)
    relevance_hits = len(tokens & question_terms)
    relevance = min(1.0, relevance_hits / max(3.0, min(10.0, len(question_terms) * 0.18)))

    category_signals = _CATEGORY_SIGNALS.get(question.category, set())
    category_coverage = min(1.0, len(tokens & category_signals) / 4.0)

    completeness = min(1.0, len(words) / 75.0)
    if len(words) < 12:
        completeness *= 0.55

    reasoning_markers = {
        "because", "therefore", "since", "tradeoff", "example", "first", "then",
        "however", "complexity", "edge", "result", "measured", "compared",
    }
    reasoning = min(1.0, len(tokens & reasoning_markers) / 3.0)
    if re.search(r"\b(?:o\([^)]+\)|\d+(?:\.\d+)?%|\d+x)\b", answer.casefold()):
        reasoning = min(1.0, reasoning + 0.2)

    if question.category == "Behavioral":
        behavioral_structure = {"situation", "task", "action", "result"}
        star_hits = len(tokens & behavioral_structure)
        ownership = bool(tokens & {"i", "my", "led", "owned", "decided", "implemented"})
        outcome = bool(re.search(r"\b\d+(?:\.\d+)?(?:%|x)?\b", answer)) or bool(
            tokens & {"improved", "reduced", "increased", "saved", "resolved", "delivered"}
        )
        category_coverage = min(1.0, 0.18 * star_hits + 0.22 * ownership + 0.22 * outcome)

    correctness = min(1.0, 0.7 * concept_coverage + 0.3 * category_coverage)
    overall = (
        0.38 * correctness
        + 0.22 * completeness
        + 0.22 * relevance
        + 0.18 * reasoning
    )
    if len(words) < 8:
        overall = min(overall, 0.20)
    overall = max(0.0, min(1.0, overall))

    if overall >= 0.82 and concept_coverage >= 0.65:
        classification = "CORRECT"
    elif overall >= 0.65:
        classification = "MOSTLY_CORRECT"
    elif overall >= 0.38:
        classification = "PARTIALLY_CORRECT"
    elif relevance < 0.12:
        classification = "IRRELEVANT"
    else:
        classification = "INCORRECT"

    return AnswerAnalysis(
        classification=classification,
        correctness=round(correctness, 2),
        completeness=round(completeness, 2),
        relevance=round(relevance, 2),
        reasoning=round(reasoning, 2),
        missing_concepts=missing,
        misconceptions=(),
        overall_score=round(overall, 2),
    )


def as_technical_question(question: CompanyQuestion) -> Question:
    return Question(
        id=question.id,
        question=question.prompt,
        domain=question.category,
        subtopic=f"{question.company_id}:{question.round}",
        difficulty=question.difficulty,
        question_type="COMPANY_REPORTED",
        expected_concepts=question.focus_points,
        ideal_answer=question.answer_outline,
    )


@dataclass
class CompanyPracticeSession:
    company_id: str
    questions: list[CompanyQuestion]
    evaluation_mode: str = "fast"
    answers: list[str] = field(default_factory=list)
    analyses: list[AnswerAnalysis] = field(default_factory=list)

    @classmethod
    def shuffled(
        cls,
        company_id: str,
        pool: list[CompanyQuestion],
        count: int,
        evaluation_mode: str = "fast",
    ) -> "CompanyPracticeSession":
        selected = list(pool)
        random.SystemRandom().shuffle(selected)
        return cls(
            company_id=company_id,
            questions=selected[:count],
            evaluation_mode=evaluation_mode,
        )

    @property
    def index(self) -> int:
        return len(self.answers)

    @property
    def current_question(self) -> CompanyQuestion | None:
        return self.questions[self.index] if self.index < len(self.questions) else None

    @property
    def completed(self) -> bool:
        return self.index >= len(self.questions)

    def record(self, answer: str, analysis: AnswerAnalysis) -> None:
        if self.completed:
            raise RuntimeError("company practice session is already complete")
        if not StructuredOutputValidator().valid_analysis(analysis):
            analysis = evaluate_company_fast(self.current_question, answer)
        self.answers.append(answer)
        self.analyses.append(analysis)

    def report(self) -> dict:
        category_values: dict[str, list[float]] = defaultdict(list)
        for question, analysis in zip(self.questions, self.analyses):
            category_values[question.category].append(analysis.overall_score)
        category_scores = {
            category: round(100 * sum(values) / len(values))
            for category, values in category_values.items()
        }
        overall = round(100 * sum(a.overall_score for a in self.analyses) / max(1, len(self.analyses)))
        return {
            "company_id": self.company_id,
            "questions_answered": len(self.answers),
            "overall_score": overall,
            "category_scores": category_scores,
            "strengths": sorted(category for category, score in category_scores.items() if score >= 70),
            "focus_areas": sorted(category for category, score in category_scores.items() if score < 60),
        }


def feedback_for(analysis: AnswerAnalysis) -> str:
    if analysis.overall_score >= 0.8:
        prefix = "Strong answer. Your core approach and explanation were convincing."
    elif analysis.overall_score >= 0.6:
        prefix = "Good foundation, but the answer needs more precision or depth."
    elif analysis.overall_score >= 0.4:
        prefix = "Partially correct. Make the approach more structured and justify key decisions."
    else:
        prefix = "The answer needs a clearer approach before implementation details."
    if analysis.missing_concepts:
        return f"{prefix} Revisit: {', '.join(analysis.missing_concepts[:4])}."
    return prefix
