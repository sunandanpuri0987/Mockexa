from __future__ import annotations

import asyncio
import logging
import random
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

from app.auth import get_current_user_id, get_raw_jwt_token
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
from app.repository import SupabaseRepository
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
from app.utils.session_store import company_reports, company_sessions, completed_sessions


router = APIRouter(prefix="/company", tags=["company practice"])
logger = logging.getLogger("mockexa.company")
VALID_CATEGORIES = {"DSA", "Technical", "System Design", "Behavioral"}
class CompanySessionLockManager:
    """Reference-counted process-local locks without retaining finished IDs."""

    def __init__(self):
        self._locks: dict[str, list] = {}
        self._global_lock = asyncio.Lock()

    @asynccontextmanager
    async def lock(self, session_id: str):
        async with self._global_lock:
            entry = self._locks.setdefault(session_id, [asyncio.Lock(), 0])
            entry[1] += 1
        try:
            async with entry[0]:
                yield
        finally:
            async with self._global_lock:
                entry[1] -= 1
                if entry[1] == 0:
                    self._locks.pop(session_id, None)


company_session_locks = CompanySessionLockManager()


def _normalize_categories(categories: list[str] | None) -> tuple[list[str], list[str]]:
    lookup = {category.casefold(): category for category in VALID_CATEGORIES}
    normalized: list[str] = []
    invalid: list[str] = []
    for category in categories or []:
        value = lookup.get(category.casefold())
        if value is None:
            invalid.append(category)
        elif value not in normalized:
            normalized.append(value)
    return normalized, sorted(set(invalid))


def _pool(company_id: str, categories: list[str] | None = None, role: str | None = None):
    values = [question for question in QUESTIONS if question.company_id == company_id]
    wanted = {value.casefold() for value in (categories or []) if value.strip()}
    if wanted:
        values = [question for question in values if question.category.casefold() in wanted]
    if role and role.strip() and role.casefold() not in {"all", "any"}:
        role_key = role.casefold()
        exact_role = [question for question in values if role_key in question.role.casefold()]
        if exact_role:
            values = exact_role
        else:
            # The reported-question catalog currently names many prompts under
            # broad Software Engineer roles. For other onboarding roles, keep
            # only the interview areas that transfer to that role instead of
            # returning an empty round.
            if "product" in role_key or "business analyst" in role_key:
                compatible = {"behavioral", "system design", "technical"}
            elif "data" in role_key:
                compatible = {"technical", "dsa", "behavioral"}
            elif "architect" in role_key:
                compatible = {"system design", "technical", "behavioral"}
            elif any(term in role_key for term in ("software", "developer", "engineer")):
                compatible = {"dsa", "technical", "system design"}
            else:
                compatible = set()
            if compatible:
                role_relevant = [question for question in values if question.category.casefold() in compatible]
                values = role_relevant
            else:
                values = []
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
    company_id = company_id.casefold()
    if company_id not in COMPANY_BY_ID:
        raise HTTPException(status_code=404, detail="unsupported company")
    normalized_categories, invalid = _normalize_categories(categories)
    if invalid:
        raise HTTPException(status_code=422, detail=f"unsupported categories: {', '.join(invalid)}")
    values = _pool(company_id, normalized_categories, role)
    if shuffle:
        random.SystemRandom().shuffle(values)
    return [_question_out(question) for question in values[:limit]]


@router.post("/start", response_model=CompanyStartResponse)
async def start(request: CompanyStartRequest, user_id: str = Depends(get_current_user_id)):
    company_id = request.company_id.casefold()
    if company_id not in COMPANY_BY_ID:
        raise HTTPException(status_code=404, detail="unsupported company")
    normalized_categories, invalid = _normalize_categories(request.categories)
    if invalid:
        raise HTTPException(status_code=422, detail=f"unsupported categories: {', '.join(sorted(set(invalid)))}")
    pool = _pool(company_id, normalized_categories, request.role)
    if not pool:
        raise HTTPException(status_code=422, detail="no reported questions match these filters")
    count = min(request.question_count, len(pool))
    session = CompanyPracticeSession.shuffled(
        company_id,
        pool,
        count,
        evaluation_mode=request.evaluation_mode,
        target_role=request.role or "",
    )
    session_id = str(uuid.uuid4())
    company_sessions.save(session_id, user_id, session)
    return CompanyStartResponse(
        session_id=session_id,
        company=_company_out(company_id),
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
    async with company_session_locks.lock(request.session_id):
        session = company_sessions.load(request.session_id, user_id)
        if session is None:
            raise HTTPException(status_code=404, detail="unknown or expired company session")

        cached = session.cached_response(request.question_id)
        if cached is not None:
            return CompanyAnswerResponse.model_validate(cached)

        question = session.current_question
        if question is None:
            raise HTTPException(status_code=409, detail="company practice session is already complete")
        if request.question_id is not None and request.question_id != question.id:
            raise HTTPException(status_code=409, detail="this answer belongs to an earlier company question")
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
                analysis = await asyncio.wait_for(
                    asyncio.to_thread(evaluator.evaluate, technical_question, request.answer),
                    timeout=6.0,
                )
            except Exception:
                analysis = None
        if analysis is None or not StructuredOutputValidator().valid_analysis(analysis):
            analysis = evaluate_company_fast(question, request.answer)
        session.record(request.answer, analysis)
        next_question = session.current_question
        average = sum(item.overall_score for item in session.analyses) / len(session.analyses)
        response = CompanyAnswerResponse(
            session_id=request.session_id,
            evaluation=CompanyEvaluationOut(
                classification=analysis.classification,
                correctness=analysis.correctness,
                completeness=analysis.completeness,
                relevance=analysis.relevance,
                reasoning=analysis.reasoning,
                overall_score=analysis.overall_score,
                missing_concepts=list(analysis.missing_concepts),
                feedback=analysis.feedback or feedback_for(analysis),
            ),
            reviewed_question=_review_out(question),
            next_question=_question_out(next_question) if next_question else None,
            question_number=min(session.index + 1, len(session.questions)),
            total_questions=len(session.questions),
            average_score=round(average, 3),
            completed=session.completed,
        )
        session.cache_response(question.id, response.model_dump())
        return response


@router.post("/finish/{session_id}", response_model=CompanyFinishResponse)
async def finish(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    async with company_session_locks.lock(session_id):
        cached = company_reports.load(session_id, user_id)
        if cached is not None:
            return cached
        session = company_sessions.load(session_id, user_id)
        if session is None:
            raise HTTPException(status_code=404, detail="unknown or expired company session")
        if not session.answers:
            raise HTTPException(status_code=409, detail="answer at least one question before finishing")
        if not session.completed:
            raise HTTPException(status_code=409, detail="complete all company questions before finishing")
        report = session.report()
        company = COMPANY_BY_ID[session.company_id]
        response = CompanyFinishResponse(
            session_id=session_id,
            company_id=company.id,
            company_name=company.name,
            questions_answered=report["questions_answered"],
            overall_score=report["overall_score"],
            category_scores=report["category_scores"],
            strengths=report["strengths"],
            focus_areas=report["focus_areas"],
        )
        transcript: list[dict[str, str]] = []
        for question, candidate_answer in zip(session.questions, session.answers):
            transcript.append({"speaker": f"{company.name} Interviewer", "text": question.prompt})
            transcript.append({"speaker": "You", "text": candidate_answer})
        now = datetime.now(timezone.utc).isoformat()
        completed_sessions.add_completed_session(user_id, {
            "id": session_id,
            "kind": "company",
            "topic": f"{company.name} Practice",
            "date": "Today",
            "duration": f"{max(1, len(session.answers) * 3)} min",
            "score": report["overall_score"],
            "created_at": now,
            "report": {
                "summary": f"Completed {report['questions_answered']} {company.name} interview questions.",
                "overall_score": report["overall_score"],
                "category_scores": report["category_scores"],
                "strengths": report["strengths"],
                "focus_areas": report["focus_areas"],
                "questions_answered": report["questions_answered"],
            },
            "transcript": transcript,
        })
        if settings.use_supabase_persistence:
            try:
                repo = SupabaseRepository()
                await repo.ensure_profile(user_id, raw_token)
                await repo.create_session({
                    "id": session_id,
                    "user_id": user_id,
                    "kind": "company",
                    "role": session.target_role or "Candidate",
                    "domains": sorted(report["category_scores"].keys()),
                    "topic": f"{company.name} Practice",
                    "duration_min": max(1, len(session.answers) * 3),
                    "question_count": len(session.questions),
                }, raw_token)
                await repo.upsert_feedback({
                    "session_id": session_id,
                    "overall_score": report["overall_score"],
                    "scores": {"category_scores": report["category_scores"]},
                    "strengths": report["strengths"],
                    "weaknesses": report["focus_areas"],
                    "missing_concepts": [],
                    "recommendations": report["focus_areas"],
                    "summary": f"Completed {report['questions_answered']} {company.name} interview questions.",
                }, raw_token)
                await repo.update_session(session_id, user_id, raw_token, {"status": "completed"})
            except Exception as exc:
                # The finished report remains available locally; a temporary
                # cloud outage must not discard a candidate's completed round.
                logger.warning("company_history_cloud_sync_failed session_id=%s error=%s", session_id, exc)
        try:
            from app.controllers.gd_friends import grant_session_reward
            grant_session_reward(user_id, session_id, report["overall_score"], "company")
        except Exception:
            pass
        company_reports.save(session_id, user_id, response)
        company_sessions.delete(session_id, user_id)
        return response
