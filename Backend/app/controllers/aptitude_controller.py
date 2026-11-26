from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
import random
import time

from app.data.aptitude_questions import AptitudeQuestion


@dataclass
class AptitudeAnswer:
    question_id: str
    selected_index: int
    correct: bool


@dataclass
class AptitudeSession:
    questions: list[AptitudeQuestion]
    duration_seconds: int
    target_role: str = ""
    started_at: float = field(default_factory=time.monotonic)
    answers: list[AptitudeAnswer] = field(default_factory=list)
    cached_responses: dict[str, dict] = field(default_factory=dict)

    @classmethod
    def shuffled(cls, pool: list[AptitudeQuestion], count: int, duration_seconds: int) -> "AptitudeSession":
        selected = list(pool)
        random.SystemRandom().shuffle(selected)
        return cls(questions=selected[:count], duration_seconds=duration_seconds)

    @property
    def index(self) -> int:
        return len(self.answers)

    @property
    def current_question(self) -> AptitudeQuestion | None:
        return self.questions[self.index] if self.index < len(self.questions) else None

    @property
    def completed(self) -> bool:
        return self.index >= len(self.questions)

    @property
    def elapsed_seconds(self) -> int:
        return max(0, int(time.monotonic() - self.started_at))

    @property
    def expired(self) -> bool:
        return self.elapsed_seconds >= self.duration_seconds

    def record(self, question_id: str, selected_index: int) -> AptitudeAnswer:
        question = self.current_question
        if question is None or question.id != question_id:
            raise ValueError("answer does not match the current aptitude question")
        answer = AptitudeAnswer(
            question_id=question_id,
            selected_index=selected_index,
            correct=selected_index == question.correct_index,
        )
        self.answers.append(answer)
        return answer

    def report(self) -> dict:
        category_values: dict[str, list[bool]] = defaultdict(list)
        by_id = {answer.question_id: answer for answer in self.answers}
        for question in self.questions:
            if question.id in by_id:
                category_values[question.category].append(by_id[question.id].correct)

        category_scores = {
            category: round(100 * sum(values) / len(values))
            for category, values in category_values.items()
        }
        correct = sum(answer.correct for answer in self.answers)
        total = len(self.questions)
        overall = round(100 * correct / max(1, total))
        return {
            "total_questions": total,
            "attempted": len(self.answers),
            "correct": correct,
            "incorrect": len(self.answers) - correct,
            "unanswered": total - len(self.answers),
            "overall_score": overall,
            "category_scores": category_scores,
            "time_taken_seconds": min(self.elapsed_seconds, self.duration_seconds),
            "passed": overall >= 60,
            "strengths": sorted(name for name, score in category_scores.items() if score >= 70),
            "focus_areas": sorted(name for name, score in category_scores.items() if score < 60),
        }
