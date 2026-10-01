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
from typing import Any


@dataclass
class _OwnedSession:
    owner_user_id: str
    value: Any


class InMemorySessionStore:
    def __init__(self):
        self._sessions: dict[str, _OwnedSession] = {}

    def save(self, session_id: str, owner_user_id: str, value: Any) -> None:
        self._sessions[session_id] = _OwnedSession(owner_user_id=owner_user_id, value=value)

    def load(self, session_id: str, owner_user_id: str) -> Any | None:
        entry = self._sessions.get(session_id)
        if entry is None:
            return None
        if entry.owner_user_id != owner_user_id:
            return None  # ownership mismatch — treated as "not found" to the caller
        return entry.value

    def clear(self) -> None:
        self._sessions.clear()

    def delete(self, session_id: str, owner_user_id: str) -> None:
        entry = self._sessions.get(session_id)
        if entry is not None and entry.owner_user_id == owner_user_id:
            del self._sessions[session_id]


class CompletedSessionsStore:
    def __init__(self):
        self._user_sessions: dict[str, list[dict]] = {}

    def clear(self) -> None:
        self._user_sessions.clear()

    def add_completed_session(self, owner_user_id: str, session_data: dict) -> None:
        if owner_user_id not in self._user_sessions:
            self._user_sessions[owner_user_id] = []
        # Replace if existing id
        self._user_sessions[owner_user_id] = [
            s for s in self._user_sessions[owner_user_id] if s.get("id") != session_data.get("id")
        ]
        self._user_sessions[owner_user_id].insert(0, session_data)

    def get_user_sessions(self, owner_user_id: str) -> list[dict]:
        return self._user_sessions.get(owner_user_id, [])

    def get_session_detail(self, owner_user_id: str, session_id: str) -> dict | None:
        for s in self.get_user_sessions(owner_user_id):
            if s.get("id") == session_id:
                return s
        return None



# Process-wide singleton for now. Fine for a single-process dev server; not
# fine for multi-worker/production — flagged above.
technical_sessions = InMemorySessionStore()
gd_sessions = InMemorySessionStore()
hr_sessions = InMemorySessionStore()
company_sessions = InMemorySessionStore()
completed_sessions = CompletedSessionsStore()
