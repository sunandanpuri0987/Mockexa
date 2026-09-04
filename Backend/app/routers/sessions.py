from __future__ import annotations
from typing import Any
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.auth import get_current_user_id, get_raw_jwt_token
from app.config import Settings, get_settings
from app.repository import SupabaseRepository, RepositoryError, NotFoundError
from app.utils.session_store import completed_sessions

router = APIRouter(prefix="/sessions", tags=["sessions"])

class SessionSummaryOut(BaseModel):
    id: str
    kind: str
    topic: str
    date: str
    duration: str
    score: int
    created_at: str | None = None

class SessionDetailOut(BaseModel):
    id: str
    kind: str
    topic: str
    date: str
    duration: str
    score: int
    user_id: str
    created_at: str | None = None
    report: dict[str, Any] | None = None
    transcript: list[dict[str, Any]] = []

def _format_date(raw_date: Any) -> str:
    if not raw_date:
        return "Recent"
    date_str = str(raw_date)
    if "T" in date_str:
        try:
            iso_part = date_str.split("T")[0]
            dt = datetime.strptime(iso_part, "%Y-%m-%d")
            today_str = datetime.now().strftime("%Y-%m-%d")
            if iso_part == today_str:
                return "Today"
            return dt.strftime("%b %d, %Y")
        except Exception:
            return date_str.split("T")[0]
    return date_str

@router.get("", response_model=list[SessionSummaryOut])
async def list_user_sessions(
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        try:
            db_sessions = await repo.sessions(user_id, raw_token)
            result = []
            for s in db_sessions:
                sid = s["id"]
                fb = None
                try:
                    fb = await repo.feedback(sid, raw_token)
                except Exception:
                    fb = None
                score = fb.get("overall_score", 0) if (fb and isinstance(fb, dict)) else 0
                kind = s.get("kind", "technical")
                topic = s.get("topic") or s.get("role") or "Interview Practice"
                started = s.get("started_at")
                date_formatted = _format_date(started)
                result.append(SessionSummaryOut(
                    id=sid,
                    kind=kind,
                    topic=topic,
                    date=date_formatted,
                    duration=f"{s.get('duration_min', 15)} min",
                    score=score,
                    created_at=str(started) if started else None
                ))
            return result
        except RepositoryError as exc:
            raise HTTPException(status_code=503, detail=f"Database persistent session history unavailable: {exc}")
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Failed to fetch session history: {exc}")

    in_mem = completed_sessions.get_user_sessions(user_id)
    return [
        SessionSummaryOut(
            id=s["id"],
            kind=s.get("kind", "technical"),
            topic=s.get("topic", "Interview Practice"),
            date=s.get("date", "Today"),
            duration=s.get("duration", "15 min"),
            score=s.get("score", 0),
            created_at=s.get("created_at")
        )
        for s in in_mem
    ]

@router.get("/{session_id}", response_model=SessionDetailOut)
async def get_user_session_detail(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        try:
            db_session = await repo.session(session_id, user_id, raw_token)
        except NotFoundError:
            raise HTTPException(status_code=404, detail="Session not found or access denied.")
        except RepositoryError as exc:
            raise HTTPException(status_code=503, detail=f"Database unreachable: {exc}")

        fb = None
        try:
            fb = await repo.feedback(session_id, raw_token)
        except Exception:
            fb = None
            
        score = fb.get("overall_score", 0) if (fb and isinstance(fb, dict)) else 0
        kind = db_session.get("kind", "technical")
        topic = db_session.get("topic") or db_session.get("role") or "Interview Practice"
        started = db_session.get("started_at")
        date_formatted = _format_date(started)
        
        transcript = []
        try:
            if kind in ("technical", "hr"):
                answers = await repo.answers(session_id, raw_token)
                for ans in answers:
                    q_info = ans.get("questions") or {}
                    prompt = q_info.get("prompt") if isinstance(q_info, dict) else "Question"
                    if prompt:
                        transcript.append({"speaker": "Interviewer", "text": prompt})
                    if ans.get("content"):
                        transcript.append({"speaker": "You", "text": ans["content"]})
            elif kind == "gd":
                msgs = await repo.messages(session_id, raw_token)
                for m in msgs:
                    transcript.append({"speaker": m.get("speaker", "Speaker"), "text": m.get("content", "")})
        except Exception:
            pass

        report_data = fb if fb else {}

        return SessionDetailOut(
            id=session_id,
            kind=kind,
            topic=topic,
            date=date_formatted,
            duration=f"{db_session.get('duration_min', 15)} min",
            score=score,
            user_id=user_id,
            created_at=str(started) if started else None,
            report=report_data,
            transcript=transcript
        )

    detail = completed_sessions.get_session_detail(user_id, session_id)
    if detail is None:
        raise HTTPException(status_code=404, detail="Session not found or access denied.")

    return SessionDetailOut(
        id=detail["id"],
        kind=detail.get("kind", "technical"),
        topic=detail.get("topic", "Interview Practice"),
        date=detail.get("date", "Today"),
        duration=detail.get("duration", "15 min"),
        score=detail.get("score", 0),
        user_id=user_id,
        created_at=detail.get("created_at"),
        report=detail.get("report", {}),
        transcript=detail.get("transcript", [])
    )
