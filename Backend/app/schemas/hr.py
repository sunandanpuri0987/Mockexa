from __future__ import annotations

from pydantic import BaseModel, Field


class HRStartRequest(BaseModel):
    name: str
    target_role: str
    experience: str
    max_questions: int = Field(default=5, ge=1, le=10)
    interview_style: str = "General HR"
    resume_context: str | None = None
    job_description: str | None = None


class HRQuestionOut(BaseModel):
    id: str
    question: str
    category: str


class HRStartResponse(BaseModel):
    session_id: str
    question: HRQuestionOut


class HRAnswerRequest(BaseModel):
    session_id: str
    answer: str


class HREvaluationOut(BaseModel):
    clarity: float = Field(ge=0.0, le=1.0)
    specificity: float = Field(ge=0.0, le=1.0)
    ownership: float = Field(ge=0.0, le=1.0)
    communication: float = Field(ge=0.0, le=1.0)
    teamwork: float = Field(ge=0.0, le=1.0)
    leadership: float = Field(ge=0.0, le=1.0)
    problem_solving: float = Field(ge=0.0, le=1.0)
    feedback: str
    overall_score: float = Field(ge=0.0, le=1.0)


class HRAnswerResponse(BaseModel):
    session_id: str
    evaluation: HREvaluationOut
    next_question: HRQuestionOut | None
    completed: bool


class HRFinishResponse(BaseModel):
    session_id: str
    report: dict
