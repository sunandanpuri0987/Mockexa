from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user_id, get_raw_jwt_token
from app.config import Settings, get_settings
from app.controllers.hr_controller import CuratedHRBackend, HRController
from app.controllers.hr_gemini_backend import GeminiHRBackend
from app.providers.model_router import ModelRouter
from app.repository import SupabaseRepository
from app.schemas.hr import (
    HRAnswerRequest,
    HRAnswerResponse,
    HREvaluationOut,
    HRFinishResponse,
    HRQuestionOut,
    HRStartRequest,
    HRStartResponse,
)
from app.utils.session_store import hr_sessions

router = APIRouter(prefix="/hr", tags=["hr"])


def _backend_for(settings: Settings):
    if not settings.gemini_api_key:
        return CuratedHRBackend()
    from app.providers.gemini_backend import GeminiBackend
    # Allow full retries and 15s timeout so Gemini fallback model (gemini-3.5-flash-lite) seamlessly succeeds
    resilient_config = settings.model_copy(update={"gemini_timeout_seconds": max(15.0, settings.gemini_timeout_seconds), "gemini_max_retries": max(3, settings.gemini_max_retries)})
    router_ = ModelRouter(resilient_config, GeminiBackend(resilient_config))
    return GeminiHRBackend(router_, fallback=CuratedHRBackend())


def _question_out(q) -> HRQuestionOut:
    return HRQuestionOut(id=q.id, question=q.question, category=q.category)


@router.post(
    "/start",
    response_model=HRStartResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def start(
    request: HRStartRequest,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    backend = _backend_for(settings)
    controller = HRController(backend=backend)

    try:
        first_question = controller.start(
            max_questions=request.max_questions,
            interview_style=request.interview_style,
            candidate_name=request.name,
            target_role=request.target_role,
            experience=request.experience,
            resume_context=request.resume_context or "",
            job_description=request.job_description or "",
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        # Fix 4: Ensure the user profile row exists before creating a session
        # (sessions.user_id references profiles.id, so FK will fail without this)
        await repo.ensure_profile(user_id, raw_token)
        session_data = {
            "user_id": user_id,
            "kind": "hr",
            "role": request.target_role,
            "domains": [request.interview_style],
            "topic": request.name,
            "duration_min": 30,
            "question_count": request.max_questions,
        }
        db_session = await repo.create_session(session_data, raw_token)
        session_id = db_session["id"]
    else:
        session_id = str(uuid.uuid4())
        hr_sessions.save(session_id, user_id, controller)

    return HRStartResponse(session_id=session_id, question=_question_out(first_question))


@router.post(
    "/answer",
    response_model=HRAnswerResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def answer(
    request: HRAnswerRequest,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    backend = _backend_for(settings)

    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        try:
            db_session = await repo.session(request.session_id, user_id, raw_token)
        except Exception as exc:
            raise HTTPException(status_code=404, detail="unknown or expired session_id") from exc

        prior_answers = await repo.answers(request.session_id, raw_token)
        target_role = str(db_session.get("role") or "")
        candidate_name = str(db_session.get("topic") or "")
        try:
            controller = HRController.from_history(
                max_questions=db_session.get("question_count", 5),
                history=prior_answers,
                backend=backend,
                interview_style=(db_session.get("domains") or ["General HR"])[0],
                candidate_name=candidate_name,
                target_role=target_role,
            )
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Failed to reconstruct state: {exc}") from exc
    else:
        controller = hr_sessions.load(request.session_id, user_id)
        if controller is None:
            raise HTTPException(status_code=404, detail="unknown or expired session_id")

    if not request.answer.strip():
        raise HTTPException(status_code=422, detail="answer must not be empty")

    try:
        evaluation, next_q = controller.submit_answer(request.answer)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    if settings.use_supabase_persistence:
        # The just-answered question is the last entry appended in submit_answer
        answered_question = controller.history[-1][0]
        evaluation_json = {
            "question_id": answered_question.id,
            "question_text": answered_question.question,
            "question_category": answered_question.category,
            "clarity": evaluation.clarity,
            "specificity": evaluation.specificity,
            "ownership": evaluation.ownership,
            "communication": evaluation.communication,
            "teamwork": evaluation.teamwork,
            "leadership": evaluation.leadership,
            "problem_solving": evaluation.problem_solving,
            "feedback": evaluation.feedback,
            "overall_score": evaluation.overall_score,
            "needs_follow_up": evaluation.needs_follow_up,
            "follow_up_question": evaluation.follow_up_question,
            "follow_up_category": evaluation.follow_up_category,
            "probe_focus": evaluation.probe_focus,
            "pressure_level": evaluation.pressure_level,
            "observed_signal": evaluation.observed_signal,
        }
        # Fix 1: answers table requires answer_type NOT NULL.
        # correctness: map overall_score (0-1) to numeric(3,2).
        # clarity: map clarity (0-1) to smallint(0-100) for DB storage only; API unchanged.
        # The deployed answers table references the shared seeded questions
        # table. Dynamic HR follow-ups therefore use stable storage slots;
        # their real id/text/category remain in evaluation_json above.
        hr_storage_question_ids = [
            "hr-001", "hr-002", "ds-array-list", "ds-hash", "ds-tree",
            "alg-binary", "alg-dp", "alg-sort", "os-thread", "db-acid",
        ]
        storage_question_id = hr_storage_question_ids[len(controller.history) - 1]
        await repo.add_answer({
            "session_id": request.session_id,
            "question_id": storage_question_id,
            "content": request.answer,
            "answer_type": "text",
            "correctness": round(max(0.0, min(1.0, evaluation.overall_score)), 2),
            "clarity": max(0, min(100, int(round(evaluation.clarity * 100)))) if evaluation.clarity >= 0 else None,
            "evaluation": evaluation_json,
        }, raw_token)

        if next_q is None:
            await repo.update_session(request.session_id, user_id, raw_token, {"status": "completed"})

    return HRAnswerResponse(
        session_id=request.session_id,
        evaluation=HREvaluationOut(
            clarity=evaluation.clarity,
            specificity=evaluation.specificity,
            ownership=evaluation.ownership,
            communication=evaluation.communication,
            teamwork=evaluation.teamwork,
            leadership=evaluation.leadership,
            problem_solving=evaluation.problem_solving,
            feedback=evaluation.feedback,
            overall_score=evaluation.overall_score,
        ),
        next_question=_question_out(next_q) if next_q else None,
        completed=next_q is None,
    )


@router.post(
    "/finish/{session_id}",
    response_model=HRFinishResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def finish(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    backend = _backend_for(settings)

    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        try:
            db_session = await repo.session(session_id, user_id, raw_token)
            prior_answers = await repo.answers(session_id, raw_token)
        except Exception as exc:
            raise HTTPException(status_code=404, detail="unknown or expired session_id") from exc

        controller = HRController.from_history(
            max_questions=db_session.get("question_count", 5),
            history=prior_answers,
            backend=backend,
            interview_style=(db_session.get("domains") or ["General HR"])[0],
        )
    else:
        controller = hr_sessions.load(session_id, user_id)
        if controller is None:
            raise HTTPException(status_code=404, detail="unknown or expired session_id")

    try:
        report = controller.report()
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        # Fix 2: feedback table has no 'metrics' column. Map to existing schema columns.
        # Fix 3: overall_score DB column is smallint(0-100); API report keeps the 0.0-1.0 float.
        metrics = report.get("metrics", {})
        feedback_summary = report.get("feedback_summary", [])
        feedback_data = {
            "session_id": session_id,
            "overall_score": int(round(report.get("overall_score", 0.0) * 100)),  # Fix 3: 0-1 → 0-100
            "scores": metrics,                        # per-dimension float scores stored in jsonb
            "strengths": report.get("strengths", []),
            "weaknesses": report.get("weaknesses", []),
            "missing_concepts": [],                   # HR report has no missing_concepts; required by schema
            "recommendations": [],                    # HR report has no recommendations; required by schema
            "summary": ", ".join(
                f"{item['question_id']}: {round(item['score'], 2)}"
                for item in feedback_summary
            ),
        }
        await repo.upsert_feedback(feedback_data, raw_token)
        await repo.update_session(session_id, user_id, raw_token, {"status": "completed"})
    else:
        hr_sessions.delete(session_id, user_id)
        session_summary = {
            "id": session_id,
            "kind": "hr",
            "topic": "HR Behavioral Interview",
            "date": "Today",
            "duration": f"{len(controller.history) * 3} min" if (controller and controller.history) else "10 min",
            "score": int(round(report.get("overall_score", 0.0) * 100)),
            "report": report,
            "transcript": [
                {"speaker": "HR Interviewer", "text": item[0].question} for item in (controller.history if controller and controller.history else [])
            ]
        }
        from app.utils.session_store import completed_sessions
        completed_sessions.add_completed_session(user_id, session_summary)

    from app.controllers.gd_friends import grant_session_reward
    grant_session_reward(user_id, session_id, report.get("overall_score", 0.0) * 100, "hr")
    return HRFinishResponse(session_id=session_id, report=report)
