from __future__ import annotations

from pydantic import BaseModel, Field


class TechnicalStartRequest(BaseModel):
    name: str
    target_role: str
    experience: str
    skills: list[str] = Field(default_factory=list)
    selected_domains: list[str] = Field(default_factory=lambda: ["Data Structures"])
    desired_difficulty: int = Field(default=3, ge=1, le=5)
    mode: str = Field(default="PRACTICE")
    max_questions: int = Field(default=10, ge=1, le=15)
    resume_context: str | None = None
    job_description: str | None = None


class QuestionOut(BaseModel):
    id: str
    question: str
    domain: str
    subtopic: str
    difficulty: int
    question_type: str


class TechnicalStartResponse(BaseModel):
    session_id: str
    question: QuestionOut


class TechnicalAnswerRequest(BaseModel):
    session_id: str
    answer: str
    hints_used: int = Field(default=0, ge=0)


class AnswerAnalysisOut(BaseModel):
    classification: str
    correctness: float
    completeness: float
    relevance: float
    reasoning: float
    feedback: str = ""
    missing_concepts: list[str] = Field(default_factory=list)
    misconceptions: list[str] = Field(default_factory=list)
    overall_score: float


class TechnicalAnswerResponse(BaseModel):
    session_id: str
    analysis: AnswerAnalysisOut
    decision_action: str
    next_question: QuestionOut | None
    completed: bool


class TechnicalFinishResponse(BaseModel):
    session_id: str
    report: dict
