"""
Minimal in-memory session store with owner_user_id enforcement.

Used only until Person 3's Supabase persistence boundary exists. This is
explicitly NOT production-durable (sessions vanish on process restart, not
shared across workers) and must be replaced by a real repository
implementation behind the same interface.

Repository interface (for Person 3): a persistence layer for this needs, at
minimum, `save(session_id, owner_user_id, payload: dict)`,
`load(session_id, owner_user_id) -> dict | None`, and
`delete(session_id, owner_user_id)`.

The `owner_user_id` check enforces "users must not access other users'
sessions" — the authenticated user_id is supplied by the auth dependency,
never by the client.
"""
from __future__ import annotations

from dataclasses import dataclass
import threading
import time
from typing import Any


@dataclass
class _OwnedSession:
    owner_user_id: str
    value: Any
    expires_at: float


class InMemorySessionStore:
    def __init__(self, ttl_seconds: int = 6 * 60 * 60):
        self._sessions: dict[str, _OwnedSession] = {}
        self._ttl_seconds = max(60, ttl_seconds)
        self._lock = threading.RLock()

    def save(self, session_id: str, owner_user_id: str, value: Any) -> None:
        with self._lock:
            self._sessions[session_id] = _OwnedSession(
                owner_user_id=owner_user_id,
                value=value,
                expires_at=time.monotonic() + self._ttl_seconds,
            )

    def load(self, session_id: str, owner_user_id: str) -> Any | None:
        with self._lock:
            entry = self._sessions.get(session_id)
            if entry is None:
                return None
            if entry.expires_at <= time.monotonic():
                del self._sessions[session_id]
                return None
            if entry.owner_user_id != owner_user_id:
                return None  # ownership mismatch — treated as "not found" to the caller
            return entry.value

    def clear(self) -> None:
        with self._lock:
            self._sessions.clear()

    def delete(self, session_id: str, owner_user_id: str) -> None:
        with self._lock:
            entry = self._sessions.get(session_id)
            if entry is not None and entry.owner_user_id == owner_user_id:
                del self._sessions[session_id]


class CompletedSessionsStore:
    def __init__(self, max_sessions_per_user: int = 100):
        self._user_sessions: dict[str, list[dict]] = {}
        self._max_sessions_per_user = max(1, max_sessions_per_user)
        self._lock = threading.RLock()

    def clear(self) -> None:
        with self._lock:
            self._user_sessions.clear()

    def add_completed_session(self, owner_user_id: str, session_data: dict) -> None:
        with self._lock:
            existing = self._user_sessions.get(owner_user_id, [])
            deduplicated = [
                s for s in existing if s.get("id") != session_data.get("id")
            ]
            self._user_sessions[owner_user_id] = [dict(session_data), *deduplicated][
                : self._max_sessions_per_user
            ]

    def get_user_sessions(self, owner_user_id: str) -> list[dict]:
        with self._lock:
            return [dict(session) for session in self._user_sessions.get(owner_user_id, [])]

    def get_session_detail(self, owner_user_id: str, session_id: str) -> dict | None:
        for s in self.get_user_sessions(owner_user_id):
            if s.get("id") == session_id:
                return s
        return None

    def delete_user(self, owner_user_id: str) -> None:
        with self._lock:
            self._user_sessions.pop(owner_user_id, None)



# Process-wide singleton for now. Fine for a single-process dev server; not
# fine for multi-worker/production — flagged above.
technical_sessions = InMemorySessionStore()
gd_sessions = InMemorySessionStore()
hr_sessions = InMemorySessionStore()
company_sessions = InMemorySessionStore()
company_reports = InMemorySessionStore(ttl_seconds=24 * 60 * 60)
aptitude_sessions = InMemorySessionStore()
aptitude_reports = InMemorySessionStore(ttl_seconds=24 * 60 * 60)
completed_sessions = CompletedSessionsStore()
