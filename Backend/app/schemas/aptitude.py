from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class AptitudeQuestionOut(BaseModel):
    id: str
    prompt: str
    category: str
    difficulty: int
    options: list[str]


class AptitudeStartRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    categories: list[str] = Field(default_factory=list, max_length=4)
    difficulty: int | None = Field(default=None, ge=1, le=3)
    question_count: int = Field(default=10, ge=5, le=20)
    duration_minutes: int = Field(default=15, ge=5, le=30)
    target_role: str | None = Field(default=None, max_length=80)


class AptitudeStartResponse(BaseModel):
    session_id: str
    question: AptitudeQuestionOut
    question_number: int
    total_questions: int
    duration_seconds: int


class AptitudeAnswerRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    session_id: str = Field(min_length=8, max_length=80)
    question_id: str = Field(min_length=3, max_length=100)
    selected_index: int = Field(ge=0, le=3)


class AptitudeAnswerResponse(BaseModel):
    session_id: str
    question_id: str
    selected_index: int
    correct_index: int
    is_correct: bool
    explanation: str
    correct_answers: int
    attempted: int
    next_question: AptitudeQuestionOut | None
    question_number: int
    total_questions: int
    completed: bool


class AptitudeFinishResponse(BaseModel):
    session_id: str
    total_questions: int
    attempted: int
    correct: int
    incorrect: int
    unanswered: int
    overall_score: int
    category_scores: dict[str, int]
    time_taken_seconds: int
    passed: bool
    strengths: list[str]
    focus_areas: list[str]
