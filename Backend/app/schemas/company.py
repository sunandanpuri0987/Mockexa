from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class CompanyOut(BaseModel):
    id: str
    name: str
    focus: str
    question_count: int
    categories: list[str]


class CompanyQuestionOut(BaseModel):
    id: str
    company_id: str
    prompt: str
    category: str
    role: str
    round: str
    year: int
    difficulty: int
    source_title: str
    source_url: str
    source_kind: str


class CompanyQuestionReviewOut(CompanyQuestionOut):
    focus_points: list[str]
    answer_outline: str


class CompanyStartRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    company_id: str = Field(min_length=2, max_length=60)
    categories: list[str] = Field(default_factory=list, max_length=8)
    role: str | None = Field(default=None, max_length=80)
    question_count: int = Field(default=5, ge=1, le=12)
    evaluation_mode: str = Field(default="fast", pattern="^(fast|ai)$")


class CompanyStartResponse(BaseModel):
    session_id: str
    company: CompanyOut
    question: CompanyQuestionOut
    question_number: int
    total_questions: int


class CompanyAnswerRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    session_id: str = Field(min_length=8, max_length=80)
    answer: str = Field(min_length=2, max_length=12_000)


class CompanyEvaluationOut(BaseModel):
    classification: str
    correctness: float
    completeness: float
    relevance: float
    reasoning: float
    overall_score: float
    missing_concepts: list[str]
    feedback: str


class CompanyAnswerResponse(BaseModel):
    session_id: str
    evaluation: CompanyEvaluationOut
    reviewed_question: CompanyQuestionReviewOut
    next_question: CompanyQuestionOut | None
    question_number: int
    total_questions: int
    average_score: float
    completed: bool


class CompanyFinishResponse(BaseModel):
    session_id: str
    company_id: str
    company_name: str
    questions_answered: int
    overall_score: int
    category_scores: dict[str, int]
    strengths: list[str]
    focus_areas: list[str]
