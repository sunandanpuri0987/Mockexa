from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user_id, get_raw_jwt_token
from app.repository import SupabaseRepository
from app.config import Settings, get_settings
from app.controllers.technical_controller import (
    CandidateProfile,
    CuratedTechnicalBackend,
    InterviewController,
    InterviewMode,
    CURATED_QUESTION_BANK,
)
from app.controllers.technical_gemini_backend import GeminiTechnicalBackend
from app.providers.model_router import ModelRouter
from app.schemas.technical import (
    AnswerAnalysisOut,
    QuestionOut,
    TechnicalAnswerRequest,
    TechnicalAnswerResponse,
    TechnicalFinishResponse,
    TechnicalStartRequest,
    TechnicalStartResponse,
)
from app.utils.session_store import technical_sessions

router = APIRouter(prefix="/technical", tags=["technical"])


def _backend_for(settings: Settings, use_gemini: bool):
    """Choose the evaluation backend. Defaults to GeminiBackend when use_gemini
    is enabled and GEMINI_API_KEY is configured, with robust retries and fallback.
    CuratedTechnicalBackend is used as fallback on unparseable output or when offline."""
    if use_gemini and settings.gemini_api_key:
        from app.providers.gemini_backend import GeminiBackend

        timeout = max(15.0, settings.gemini_timeout_seconds)
        retries = max(2, settings.gemini_max_retries)
        eval_settings = settings.model_copy(update={"gemini_timeout_seconds": timeout, "gemini_max_retries": retries})
        router_ = ModelRouter(eval_settings, GeminiBackend(eval_settings))
        return GeminiTechnicalBackend(router_)
    return CuratedTechnicalBackend()


def _question_out(q) -> QuestionOut:
    return QuestionOut(
        id=q.id, question=q.question, domain=q.domain,
        subtopic=q.subtopic, difficulty=q.difficulty, question_type=q.question_type,
    )


@router.post(
    "/start",
    response_model=TechnicalStartResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def start(
    request: TechnicalStartRequest,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    profile = CandidateProfile(
        name=request.name,
        target_role=request.target_role,
        experience=request.experience,
        skills=tuple(request.skills),
        selected_domains=tuple(request.selected_domains),
        desired_difficulty=request.desired_difficulty,
        resume_context=request.resume_context,
        job_description=request.job_description,
    )
    try:
        mode = InterviewMode(request.mode)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=f"invalid mode: {request.mode}") from exc

    backend = _backend_for(settings, use_gemini=settings.use_gemini)  # configured via settings
    controller = InterviewController(CURATED_QUESTION_BANK, backend=backend)
    try:
        first_question = controller.start(profile, mode, max_questions=request.max_questions)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        await repo.ensure_profile(user_id, raw_token)
        session_data = {
            "user_id": user_id,
            "kind": "technical",
            "role": request.target_role,
            "domains": request.selected_domains,
            "topic": f"{mode.value}:{first_question.id}",
            "duration_min": 60,
            "question_count": request.max_questions
        }
        db_session = await repo.create_session(session_data, raw_token)
        session_id = db_session["id"]
    else:
        session_id = str(uuid.uuid4())
        technical_sessions.save(session_id, user_id, controller)

    return TechnicalStartResponse(session_id=session_id, question=_question_out(first_question))


@router.post(
    "/answer",
    response_model=TechnicalAnswerResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def answer(
    request: TechnicalAnswerRequest,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    backend = _backend_for(settings, use_gemini=settings.use_gemini)

    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        try:
            db_session = await repo.session(request.session_id, user_id, raw_token)
        except Exception as exc:
            raise HTTPException(status_code=404, detail="unknown or expired session_id") from exc
            
        answers = await repo.answers(request.session_id, raw_token)
        profile = CandidateProfile(
            name="Restored",
            target_role=db_session.get("role", "Software Engineer"),
            experience="Unknown",
            skills=(),
            selected_domains=tuple(db_session.get("domains", [])),
            desired_difficulty=3,
        )
        raw_topic = str(db_session.get("topic", "PRACTICE"))
        if ":" in raw_topic:
            mode_str, initial_qid = raw_topic.split(":", 1)
        else:
            mode_str, initial_qid = raw_topic, None
            
        try:
            mode = InterviewMode(mode_str)
        except ValueError:
            mode = InterviewMode.PRACTICE
            
        try:
            max_q = int(db_session.get("question_count") or 5)
            controller = InterviewController.from_history(
                profile=profile,
                mode=mode,
                max_questions=max_q,
                history=answers,
                bank=CURATED_QUESTION_BANK,
                backend=backend,
                initial_question_id=initial_qid,
            )
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Failed to reconstruct state: {exc}") from exc
    else:
        controller = technical_sessions.load(request.session_id, user_id)
        if controller is None:
            raise HTTPException(status_code=404, detail="unknown or expired session_id")

    if not request.answer.strip():
        raise HTTPException(status_code=422, detail="answer must not be empty")
        
    try:
        analysis, decision, next_q = controller.submit_answer(request.answer, request.hints_used)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    if settings.use_supabase_persistence:
        turn_index = len(answers)
        current_qid = (
            controller.state.question_history[-1].id
            if controller.state and controller.state.question_history
            else "ds-hash"
        )
        
        DEFAULT_DB_QIDS = [
            'ds-array-list', 'ds-hash', 'ds-tree', 'alg-binary', 'alg-dp',
            'alg-sort', 'os-thread', 'db-acid', 'db-index', 'oop-poly',
            'se-git', 'prog-java', 'net-tcp'
        ]
        base_fallback = DEFAULT_DB_QIDS[turn_index % len(DEFAULT_DB_QIDS)]
        db_qid = f"{base_fallback}-followup" if current_qid.endswith("-followup") else base_fallback

        evaluation_json = {
            "question_id": current_qid,
            "classification": analysis.classification,
            "correctness": analysis.correctness,
            "completeness": analysis.completeness,
            "relevance": analysis.relevance,
            "reasoning": analysis.reasoning,
            "feedback": analysis.feedback,
            "missing_concepts": list(analysis.missing_concepts),
            "misconceptions": list(analysis.misconceptions),
            "overall_score": analysis.overall_score,
            "hints_used": request.hints_used
        }
        await repo.add_answer({
            "session_id": request.session_id,
            "question_id": db_qid,
            "content": request.answer,
            "answer_type": "text",
            "correctness": round(analysis.correctness, 2),
            "clarity": None,
            "evaluation": evaluation_json,
        }, raw_token)
        
        if next_q is None:
            await repo.update_session(request.session_id, user_id, raw_token, {"status": "completed"})

    return TechnicalAnswerResponse(
        session_id=request.session_id,
        analysis=AnswerAnalysisOut(
            classification=analysis.classification,
            correctness=analysis.correctness,
            completeness=analysis.completeness,
            relevance=analysis.relevance,
            reasoning=analysis.reasoning,
            feedback=analysis.feedback,
            missing_concepts=list(analysis.missing_concepts),
            misconceptions=list(analysis.misconceptions),
            overall_score=analysis.overall_score,
        ),
        decision_action=decision.action,
        next_question=_question_out(next_q) if next_q else None,
        completed=next_q is None,
    )


@router.post(
    "/finish/{session_id}",
    response_model=TechnicalFinishResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def finish(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    backend = _backend_for(settings, use_gemini=settings.use_gemini)

    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        try:
            db_session = await repo.session(session_id, user_id, raw_token)
            answers = await repo.answers(session_id, raw_token)
        except Exception as exc:
            raise HTTPException(status_code=404, detail="unknown or expired session_id") from exc
            
        profile = CandidateProfile(
            name="Restored",
            target_role=db_session.get("role", "Software Engineer"),
            experience="Unknown",
            skills=(),
            selected_domains=tuple(db_session.get("domains", [])),
            desired_difficulty=3,
        )
        try:
            mode = InterviewMode(db_session.get("topic", "PRACTICE"))
        except ValueError:
            mode = InterviewMode.PRACTICE
            
        controller = InterviewController.from_history(
            profile=profile,
            mode=mode,
            max_questions=db_session.get("question_count", 15),
            history=answers,
            bank=CURATED_QUESTION_BANK,
            backend=backend
        )
    else:
        controller = technical_sessions.load(session_id, user_id)
        if controller is None:
            raise HTTPException(status_code=404, detail="unknown or expired session_id")

    try:
        report = controller.report()
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        overall_score_int = int(round(report.get("overall_score", 0.0)))
        domain_scores = report.get("domain_scores", {})
        mastery = report.get("mastery", {})
        feedback_data = {
            "session_id": session_id,
            "overall_score": overall_score_int,
            "scores": {"domain_scores": domain_scores, "mastery": mastery},
            "strengths": [d for d, s in domain_scores.items() if s >= 70],
            "weaknesses": report.get("persistent_misconceptions", []) or report.get("focus_areas", []),
            "missing_concepts": [],
            "recommendations": report.get("focus_areas", []),
            "summary": report.get("summary") or f"Band: {report.get('performance_band')}. Questions Answered: {report.get('questions_answered')}"
        }
        await repo.upsert_feedback(feedback_data, raw_token)
        await repo.update_session(session_id, user_id, raw_token, {"status": "completed"})
    else:
        technical_sessions.delete(session_id, user_id)
        session_summary = {
            "id": session_id,
            "kind": "technical",
            "topic": controller.state.mode.value if (controller and controller.state) else "Technical Interview",
            "date": "Today",
            "duration": f"{len(controller.state.question_history) * 3} min" if (controller and controller.state and controller.state.question_history) else "15 min",
            "score": int(round(report.get("overall_score", 0.0))),
            "report": report,
            "transcript": [
                {"speaker": "AI Interviewer", "text": q.question} for q in (controller.state.question_history if controller and controller.state else [])
            ]
        }
        from app.utils.session_store import completed_sessions
        completed_sessions.add_completed_session(user_id, session_summary)

    from app.controllers.gd_friends import grant_session_reward
    grant_session_reward(user_id, session_id, report.get("overall_score", 0.0), "technical")
    return TechnicalFinishResponse(session_id=session_id, report=report)


