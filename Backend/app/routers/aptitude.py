from __future__ import annotations

import asyncio
import logging
import random
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user_id, get_raw_jwt_token
from app.config import Settings, get_settings
from app.controllers.aptitude_controller import AptitudeSession
from app.data.aptitude_questions import CATEGORIES, QUESTIONS
from app.repository import SupabaseRepository
from app.schemas.aptitude import (
    AptitudeAnswerRequest,
    AptitudeAnswerResponse,
    AptitudeFinishResponse,
    AptitudeQuestionOut,
    AptitudeStartRequest,
    AptitudeStartResponse,
)
from app.utils.session_store import aptitude_reports, aptitude_sessions, completed_sessions


router = APIRouter(prefix="/aptitude", tags=["aptitude round"])
logger = logging.getLogger("mockexa.aptitude")


class _SessionLocks:
    def __init__(self) -> None:
        self._entries: dict[str, list] = {}
        self._guard = asyncio.Lock()

    @asynccontextmanager
    async def lock(self, session_id: str):
        async with self._guard:
            entry = self._entries.setdefault(session_id, [asyncio.Lock(), 0])
            entry[1] += 1
        try:
            async with entry[0]:
                yield
        finally:
            async with self._guard:
                entry[1] -= 1
                if entry[1] == 0:
                    self._entries.pop(session_id, None)


session_locks = _SessionLocks()


def _role_categories(role: str | None) -> list[str]:
    """Return placement-test areas most relevant to the onboarding role."""
    value = (role or "").strip().casefold()
    if not value:
        return []
    if "data" in value or "business analyst" in value:
        return ["Data Interpretation", "Quantitative Aptitude", "Logical Reasoning"]
    if "product" in value:
        return ["Logical Reasoning", "Verbal Ability", "Data Interpretation"]
    if any(term in value for term in ("architect", "software", "developer", "engineer")):
        return ["Logical Reasoning", "Quantitative Aptitude", "Verbal Ability"]
    return []


def _question_out(question) -> AptitudeQuestionOut:
    return AptitudeQuestionOut(**question.public_dict())


def _normalized_categories(values: list[str]) -> list[str]:
    lookup = {category.casefold(): category for category in CATEGORIES}
    normalized: list[str] = []
    invalid: list[str] = []
    for raw in values:
        category = lookup.get(raw.casefold())
        if category is None:
            invalid.append(raw)
        elif category not in normalized:
            normalized.append(category)
    if invalid:
        raise HTTPException(status_code=422, detail=f"unsupported aptitude categories: {', '.join(sorted(set(invalid)))}")
    return normalized


@router.get("/categories", response_model=list[str])
async def categories(_: str = Depends(get_current_user_id)):
    return list(CATEGORIES)


@router.post("/start", response_model=AptitudeStartResponse)
async def start(request: AptitudeStartRequest, user_id: str = Depends(get_current_user_id)):
    selected_categories = _normalized_categories(request.categories)
    if not selected_categories:
        selected_categories = _role_categories(request.target_role)
    category_pool = [
        question for question in QUESTIONS
        if (not selected_categories or question.category in selected_categories)
    ]
    if not category_pool:
        raise HTTPException(status_code=422, detail="no aptitude questions match these filters")

    rng = random.SystemRandom()
    if request.difficulty is None:
        selected_pool = list(category_pool)
        rng.shuffle(selected_pool)
    else:
        # Prefer questions at or below the selected level, then fill from the
        # same categories so the requested round length never collapses.
        preferred = [q for q in category_pool if q.difficulty <= request.difficulty]
        fallback = [q for q in category_pool if q.difficulty > request.difficulty]
        rng.shuffle(preferred)
        rng.shuffle(fallback)
        selected_pool = preferred + fallback
    count = min(request.question_count, len(selected_pool))
    session = AptitudeSession(
        questions=selected_pool[:count],
        duration_seconds=request.duration_minutes * 60,
        target_role=request.target_role or "",
    )
    session_id = str(uuid.uuid4())
    aptitude_sessions.save(session_id, user_id, session)
    return AptitudeStartResponse(
        session_id=session_id,
        question=_question_out(session.current_question),
        question_number=1,
        total_questions=len(session.questions),
        duration_seconds=session.duration_seconds,
    )


@router.post("/answer", response_model=AptitudeAnswerResponse)
async def answer(request: AptitudeAnswerRequest, user_id: str = Depends(get_current_user_id)):
    async with session_locks.lock(request.session_id):
        session: AptitudeSession | None = aptitude_sessions.load(request.session_id, user_id)
        if session is None:
            raise HTTPException(status_code=404, detail="unknown or expired aptitude session")
        cached = session.cached_responses.get(request.question_id)
        if cached is not None:
            return AptitudeAnswerResponse.model_validate(cached)
        if session.expired:
            raise HTTPException(status_code=409, detail="Time is up. Finish the aptitude round to view your result.")
        question = session.current_question
        if question is None:
            raise HTTPException(status_code=409, detail="aptitude round is already complete")
        if question.id != request.question_id:
            raise HTTPException(status_code=409, detail="this answer belongs to an earlier aptitude question")

        recorded = session.record(question.id, request.selected_index)
        next_question = session.current_question
        response = AptitudeAnswerResponse(
            session_id=request.session_id,
            question_id=question.id,
            selected_index=request.selected_index,
            correct_index=question.correct_index,
            is_correct=recorded.correct,
            explanation=question.explanation,
            correct_answers=sum(item.correct for item in session.answers),
            attempted=len(session.answers),
            next_question=_question_out(next_question) if next_question else None,
            question_number=min(session.index + 1, len(session.questions)),
            total_questions=len(session.questions),
            completed=session.completed,
        )
        session.cached_responses[question.id] = response.model_dump()
        return response


@router.post("/finish/{session_id}", response_model=AptitudeFinishResponse)
async def finish(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    async with session_locks.lock(session_id):
        cached = aptitude_reports.load(session_id, user_id)
        if cached is not None:
            return cached
        session: AptitudeSession | None = aptitude_sessions.load(session_id, user_id)
        if session is None:
            raise HTTPException(status_code=404, detail="unknown or expired aptitude session")

        report = session.report()
        response = AptitudeFinishResponse(session_id=session_id, **report)
        answer_by_id = {answer.question_id: answer for answer in session.answers}
        transcript: list[dict[str, str]] = []
        for question in session.questions:
            transcript.append({"speaker": "Aptitude Question", "text": question.prompt})
            selected = answer_by_id.get(question.id)
            if selected is not None:
                transcript.append({
                    "speaker": "Your Answer",
                    "text": question.options[selected.selected_index],
                })
                transcript.append({
                    "speaker": "Explanation",
                    "text": question.explanation,
                })

        completed_at = datetime.now(timezone.utc).isoformat()
        completed_sessions.add_completed_session(user_id, {
            "id": session_id,
            "kind": "aptitude",
            "topic": "Aptitude Round",
            "date": "Today",
            "duration": f"{max(1, (report['time_taken_seconds'] + 59) // 60)} min",
            "score": report["overall_score"],
            "created_at": completed_at,
            "report": response.model_dump(),
            "transcript": transcript,
        })
        if settings.use_supabase_persistence:
            try:
                repo = SupabaseRepository()
                await repo.ensure_profile(user_id, raw_token)
                await repo.create_session({
                    "id": session_id,
                    "user_id": user_id,
                    "kind": "aptitude",
                    "role": session.target_role or "Candidate",
                    "domains": sorted(report["category_scores"].keys()),
                    "topic": "Aptitude Round",
                    "duration_min": max(1, (report["time_taken_seconds"] + 59) // 60),
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
                    "summary": f"{report['correct']} of {report['total_questions']} aptitude questions correct.",
                }, raw_token)
                await repo.update_session(session_id, user_id, raw_token, {"status": "completed"})
            except Exception as exc:
                logger.warning("aptitude_history_cloud_sync_failed session_id=%s error=%s", session_id, exc)
        try:
            from app.controllers.gd_friends import grant_session_reward
            grant_session_reward(user_id, session_id, report["overall_score"], "aptitude")
        except Exception:
            pass
        aptitude_reports.save(session_id, user_id, response)
        aptitude_sessions.delete(session_id, user_id)
        return response
