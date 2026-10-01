from __future__ import annotations

import asyncio
import random
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query

from app.auth import get_current_user_id
from app.config import Settings, get_settings
from app.controllers.company_controller import (
    CompanyPracticeSession,
    as_technical_question,
    evaluate_company_fast,
    feedback_for,
)
from app.controllers.technical_controller import StructuredOutputValidator
from app.controllers.technical_gemini_backend import GeminiTechnicalBackend
from app.data.company_questions import COMPANIES, COMPANY_BY_ID, QUESTIONS
from app.providers.gemini_backend import GeminiBackend
from app.providers.model_router import ModelRouter
from app.schemas.company import (
    CompanyAnswerRequest,
    CompanyAnswerResponse,
    CompanyEvaluationOut,
    CompanyFinishResponse,
    CompanyOut,
    CompanyQuestionOut,
    CompanyQuestionReviewOut,
    CompanyStartRequest,
    CompanyStartResponse,
)
from app.utils.session_store import company_sessions


router = APIRouter(prefix="/company", tags=["company practice"])
VALID_CATEGORIES = {"DSA", "Technical", "System Design", "Behavioral"}


def _pool(company_id: str, categories: list[str] | None = None, role: str | None = None):
    values = [question for question in QUESTIONS if question.company_id == company_id]
    wanted = {value.casefold() for value in (categories or []) if value.strip()}
    if wanted:
        values = [question for question in values if question.category.casefold() in wanted]
    if role and role.strip() and role.casefold() not in {"all", "any"}:
        role_key = role.casefold()
        role_matches = [question for question in values if role_key in question.role.casefold()]
        if role_matches:
            values = role_matches
    return values


def _company_out(company_id: str) -> CompanyOut:
    company = COMPANY_BY_ID[company_id]
    values = _pool(company_id)
    return CompanyOut(
        id=company.id,
        name=company.name,
        focus=company.focus,
        question_count=len(values),
        categories=sorted({question.category for question in values}),
    )


def _question_out(question) -> CompanyQuestionOut:
    return CompanyQuestionOut(**question.public_dict())


def _review_out(question) -> CompanyQuestionReviewOut:
    return CompanyQuestionReviewOut(**question.public_dict(include_answer=True))


@router.get("/companies", response_model=list[CompanyOut])
async def companies(_: str = Depends(get_current_user_id)):
    return [_company_out(company.id) for company in COMPANIES]


@router.get("/{company_id}/questions", response_model=list[CompanyQuestionOut])
async def questions(
    company_id: str,
    categories: list[str] = Query(default=[]),
    role: str | None = None,
    limit: int = Query(default=12, ge=1, le=50),
    shuffle: bool = True,
    _: str = Depends(get_current_user_id),
):
    if company_id not in COMPANY_BY_ID:
        raise HTTPException(status_code=404, detail="unsupported company")
    values = _pool(company_id, categories, role)
    if shuffle:
        random.SystemRandom().shuffle(values)
    return [_question_out(question) for question in values[:limit]]


@router.post("/start", response_model=CompanyStartResponse)
async def start(request: CompanyStartRequest, user_id: str = Depends(get_current_user_id)):
    if request.company_id not in COMPANY_BY_ID:
        raise HTTPException(status_code=404, detail="unsupported company")
    invalid = sorted(set(request.categories) - VALID_CATEGORIES)
    if invalid:
        raise HTTPException(status_code=422, detail=f"unsupported categories: {', '.join(invalid)}")
    pool = _pool(request.company_id, request.categories, request.role)
    if not pool:
        raise HTTPException(status_code=422, detail="no reported questions match these filters")
    count = min(request.question_count, len(pool))
    session = CompanyPracticeSession.shuffled(
        request.company_id,
        pool,
        count,
        evaluation_mode=request.evaluation_mode,
    )
    session_id = str(uuid.uuid4())
    company_sessions.save(session_id, user_id, session)
    return CompanyStartResponse(
        session_id=session_id,
        company=_company_out(request.company_id),
        question=_question_out(session.current_question),
        question_number=1,
        total_questions=len(session.questions),
    )


@router.post("/answer", response_model=CompanyAnswerResponse)
async def answer(
    request: CompanyAnswerRequest,
    user_id: str = Depends(get_current_user_id),
    settings: Settings = Depends(get_settings),
):
    session = company_sessions.load(request.session_id, user_id)
    if session is None:
        raise HTTPException(status_code=404, detail="unknown or expired company session")
    question = session.current_question
    if question is None:
        raise HTTPException(status_code=409, detail="company practice session is already complete")
    technical_question = as_technical_question(question)
    analysis = None
    if session.evaluation_mode == "ai" and settings.use_gemini and settings.gemini_api_key:
        try:
            # Company practice must remain interactive. Use the low-latency
            # fallback model directly and make a single bounded attempt; the
            # deterministic evaluator below is always available immediately.
            ai_settings = settings.model_copy(update={
                "gemini_model": settings.gemini_fallback_model or settings.gemini_model,
                "gemini_fallback_model": None,
                "gemini_max_retries": 1,
                "gemini_timeout_seconds": min(settings.gemini_timeout_seconds, 5.0),
            })
            evaluator = GeminiTechnicalBackend(ModelRouter(ai_settings, GeminiBackend(ai_settings)))
            analysis = await asyncio.to_thread(evaluator.evaluate, technical_question, request.answer)
        except Exception:
            analysis = None
    if analysis is None or not StructuredOutputValidator().valid_analysis(analysis):
        analysis = evaluate_company_fast(question, request.answer)
    session.record(request.answer, analysis)
    next_question = session.current_question
    average = sum(item.overall_score for item in session.analyses) / len(session.analyses)
    return CompanyAnswerResponse(
        session_id=request.session_id,
        evaluation=CompanyEvaluationOut(
            classification=analysis.classification,
            correctness=analysis.correctness,
            completeness=analysis.completeness,
            relevance=analysis.relevance,
            reasoning=analysis.reasoning,
            overall_score=analysis.overall_score,
            missing_concepts=list(analysis.missing_concepts),
            feedback=feedback_for(analysis),
        ),
        reviewed_question=_review_out(question),
        next_question=_question_out(next_question) if next_question else None,
        question_number=min(session.index + 1, len(session.questions)),
        total_questions=len(session.questions),
        average_score=round(average, 3),
        completed=session.completed,
    )


@router.post("/finish/{session_id}", response_model=CompanyFinishResponse)
async def finish(session_id: str, user_id: str = Depends(get_current_user_id)):
    session = company_sessions.load(session_id, user_id)
    if session is None:
        raise HTTPException(status_code=404, detail="unknown or expired company session")
    if not session.answers:
        raise HTTPException(status_code=409, detail="answer at least one question before finishing")
    report = session.report()
    company = COMPANY_BY_ID[session.company_id]
    company_sessions.delete(session_id, user_id)
    from app.controllers.gd_friends import grant_session_reward
    grant_session_reward(user_id, session_id, report["overall_score"], "company")
    return CompanyFinishResponse(
        session_id=session_id,
        company_id=company.id,
        company_name=company.name,
        questions_answered=report["questions_answered"],
        overall_score=report["overall_score"],
        category_scores=report["category_scores"],
        strengths=report["strengths"],
        focus_areas=report["focus_areas"],
    )
