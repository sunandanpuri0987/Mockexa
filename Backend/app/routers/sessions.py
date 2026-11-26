from __future__ import annotations
from typing import Any
from datetime import datetime
import json
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

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
    transcript: list[dict[str, Any]] = Field(default_factory=list)


def _safe_score(value: Any) -> int:
    try:
        return max(0, min(100, int(round(float(value)))))
    except (TypeError, ValueError):
        return 0


def _display_topic(kind: str, raw_topic: Any, role: Any = None) -> str:
    """Hide durable active-state envelopes from user-facing history."""
    topic = str(raw_topic or "")
    if topic.startswith("mockexa:aptitude:v1:"):
        return "Aptitude Round"
    if topic.startswith("mockexa:company:v1:"):
        try:
            payload = json.loads(topic.split(":", 3)[3])
            company_id = str(payload.get("company_id") or "").strip()
            if company_id:
                return f"{company_id.replace('-', ' ').title()} Practice"
        except (json.JSONDecodeError, TypeError, ValueError):
            pass
        return "Company Practice"
    return topic or str(role or "") or "Interview Practice"


def _local_summary(session: dict[str, Any]) -> SessionSummaryOut:
    return SessionSummaryOut(
        id=session["id"],
        kind=session.get("kind", "technical"),
        topic=session.get("topic", "Interview Practice"),
        date=session.get("date", "Today"),
        duration=session.get("duration", "15 min"),
        score=_safe_score(session.get("score", 0)),
        created_at=session.get("created_at"),
    )


def _local_detail(user_id: str, detail: dict[str, Any]) -> SessionDetailOut:
    return SessionDetailOut(
        id=detail["id"],
        kind=detail.get("kind", "technical"),
        topic=detail.get("topic", "Interview Practice"),
        date=detail.get("date", "Today"),
        duration=detail.get("duration", "15 min"),
        score=_safe_score(detail.get("score", 0)),
        user_id=user_id,
        created_at=detail.get("created_at"),
        report=detail.get("report", {}),
        transcript=detail.get("transcript", []),
    )

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
    local_result = [_local_summary(s) for s in completed_sessions.get_user_sessions(user_id)]
    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        try:
            db_sessions = await repo.sessions(user_id, raw_token)
            try:
                feedback_by_session = await repo.feedback_for_sessions(
                    [s["id"] for s in db_sessions], raw_token
                )
            except RepositoryError:
                feedback_by_session = {}
            result = []
            for s in db_sessions:
                sid = s["id"]
                fb = feedback_by_session.get(sid)
                score = fb.get("overall_score", 0) if (fb and isinstance(fb, dict)) else 0
                kind = s.get("kind", "technical")
                topic = _display_topic(kind, s.get("topic"), s.get("role"))
                started = s.get("started_at")
                date_formatted = _format_date(started)
                result.append(SessionSummaryOut(
                    id=sid,
                    kind=kind,
                    topic=topic,
                    date=date_formatted,
                    duration=f"{s.get('duration_min', 15)} min",
                    score=_safe_score(score),
                    created_at=str(started) if started else None
                ))
            # Some practice modes currently complete in the process-local store
            # while the durable repository rollout is in progress. Never hide
            # those sessions merely because Supabase persistence is enabled.
            merged = {item.id: item for item in local_result}
            merged.update({item.id: item for item in result})
            return sorted(
                merged.values(),
                key=lambda item: item.created_at or "",
                reverse=True,
            )
        except RepositoryError as exc:
            if local_result:
                return local_result
            raise HTTPException(status_code=503, detail=f"Database persistent session history unavailable: {exc}")
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Failed to fetch session history: {exc}")

    return local_result

@router.get("/{session_id}", response_model=SessionDetailOut)
async def get_user_session_detail(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    local_detail = completed_sessions.get_session_detail(user_id, session_id)
    if local_detail is not None:
        return _local_detail(user_id, local_detail)

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
        topic = _display_topic(kind, db_session.get("topic"), db_session.get("role"))
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
                    content = m.get("content", "")
                    speaker = m.get("speaker", "Speaker")
                    text = content
                    # GD messages are stored as a JSON envelope so the manager
                    # can reconstruct state. The transcript must show only the
                    # spoken response, never that internal JSON payload.
                    if isinstance(content, str):
                        try:
                            envelope = json.loads(content)
                            if isinstance(envelope, dict):
                                speaker = envelope.get("speaker") or speaker
                                text = envelope.get("response") or envelope.get("claim") or ""
                        except (json.JSONDecodeError, TypeError):
                            pass
                    transcript.append({"speaker": speaker, "text": str(text or "")})
        except Exception:
            pass

        report_data = fb if fb else {}

        return SessionDetailOut(
            id=session_id,
            kind=kind,
            topic=topic,
            date=date_formatted,
            duration=f"{db_session.get('duration_min', 15)} min",
            score=_safe_score(score),
            user_id=user_id,
            created_at=str(started) if started else None,
            report=report_data,
            transcript=transcript
        )

    raise HTTPException(status_code=404, detail="Session not found or access denied.")
