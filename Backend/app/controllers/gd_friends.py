from __future__ import annotations

import random
import re
import string
import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Any


REWARD_CATALOG = {
    "xp_boost": {
        "title": "2x XP Boost",
        "description": "Automatically doubles XP from your next contribution or completed practice session.",
        "cost": 55,
        "icon": "bolt.fill",
    },
    "coin_boost": {
        "title": "2x Coin Boost",
        "description": "Automatically doubles coins from your next contribution or completed practice session.",
        "cost": 45,
        "icon": "circle.hexagongrid.fill",
    },
    "power_boost": {
        "title": "Power Boost",
        "description": "Automatically doubles both XP and coins on your next earning event in any mode.",
        "cost": 90,
        "icon": "flame.fill",
    },
}


class RewardWalletStore:
    def __init__(self) -> None:
        self._wallets: dict[str, dict[str, Any]] = {}
        self._events: set[str] = set()
        self._lock = threading.RLock()

    def _wallet(self, user_id: str) -> dict[str, Any]:
        return self._wallets.setdefault(
            user_id,
            {"xp": 0, "coins": 0, "level": 1, "inventory": {}, "achievements": []},
        )

    def clear(self) -> None:
        with self._lock:
            self._wallets.clear()
            self._events.clear()

    def snapshot(self, user_id: str) -> dict[str, Any]:
        with self._lock:
            wallet = self._wallet(user_id)
            return {
                **wallet,
                "inventory": dict(wallet["inventory"]),
                "achievements": list(wallet["achievements"]),
                "xp_to_next_level": 250 - (wallet["xp"] % 250),
                "catalog": [{"id": key, **value} for key, value in REWARD_CATALOG.items()],
            }

    def set_display_name(self, user_id: str, display_name: str | None) -> None:
        clean = " ".join((display_name or "").strip().split())[:60]
        if not clean:
            return
        with self._lock:
            self._wallet(user_id)["display_name"] = clean

    @staticmethod
    def _public_name(wallet: dict[str, Any], user_id: str) -> str:
        name = str(wallet.get("display_name") or "").strip()
        if name:
            parts = name.split()
            return parts[0] if len(parts) == 1 else f"{parts[0]} {parts[-1][0].upper()}."
        return f"Candidate {user_id[-4:].upper()}"

    def leaderboard(self, viewer_user_id: str, limit: int = 50) -> dict[str, Any]:
        with self._lock:
            self._wallet(viewer_user_id)
            ranked = sorted(
                self._wallets.items(),
                key=lambda item: (-int(item[1].get("xp", 0)), -int(item[1].get("coins", 0)), item[0]),
            )
            entries = []
            viewer_rank = 0
            for index, (user_id, wallet) in enumerate(ranked, start=1):
                if user_id == viewer_user_id:
                    viewer_rank = index
                if index <= max(1, min(limit, 100)):
                    entries.append({
                        "rank": index,
                        "display_name": self._public_name(wallet, user_id),
                        "xp": int(wallet.get("xp", 0)),
                        "coins": int(wallet.get("coins", 0)),
                        "level": int(wallet.get("level", 1)),
                        "achievement_count": len(wallet.get("achievements", [])),
                        "is_current_user": user_id == viewer_user_id,
                    })
            viewer = self._wallet(viewer_user_id)
            return {
                "entries": entries,
                "current_user_rank": viewer_rank,
                "current_user_xp": int(viewer.get("xp", 0)),
                "total_players": len(ranked),
                "ranking_basis": "All-time XP earned from completed practice and GD contributions.",
            }

    def grant(self, user_id: str, *, xp: int, coins: int, event_id: str) -> dict[str, Any]:
        with self._lock:
            if event_id in self._events:
                return self.snapshot(user_id)
            self._events.add(event_id)
            wallet = self._wallet(user_id)
            if wallet["inventory"].get("power_boost", 0) > 0 and (xp > 0 or coins > 0):
                xp *= 2
                coins *= 2
                wallet["inventory"]["power_boost"] -= 1
            elif wallet["inventory"].get("xp_boost", 0) > 0 and xp > 0:
                xp *= 2
                wallet["inventory"]["xp_boost"] -= 1
            elif wallet["inventory"].get("coin_boost", 0) > 0 and coins > 0:
                coins *= 2
                wallet["inventory"]["coin_boost"] -= 1
            wallet["xp"] += max(0, xp)
            wallet["coins"] += max(0, coins)
            wallet["level"] = 1 + wallet["xp"] // 250
            for threshold, badge in ((1, "First Voice"), (250, "Rising Speaker"), (1000, "Discussion Leader")):
                if wallet["xp"] >= threshold and badge not in wallet["achievements"]:
                    wallet["achievements"].append(badge)
            return self.snapshot(user_id)

    def redeem(self, user_id: str, reward_id: str) -> dict[str, Any]:
        reward = REWARD_CATALOG.get(reward_id)
        if reward is None:
            raise KeyError("unknown reward")
        with self._lock:
            wallet = self._wallet(user_id)
            if wallet["coins"] < reward["cost"]:
                raise ValueError("not enough coins")
            wallet["coins"] -= reward["cost"]
            wallet["inventory"][reward_id] = wallet["inventory"].get(reward_id, 0) + 1
            return self.snapshot(user_id)


@dataclass
class FriendsGDMember:
    user_id: str
    name: str
    is_host: bool = False
    ready: bool = False
    points: int = 0
    xp_earned: int = 0
    coins_earned: int = 0
    contribution_count: int = 0


@dataclass
class FriendsGDRoom:
    id: str
    code: str
    topic: str
    mode: str
    duration_minutes: int
    max_participants: int
    host_user_id: str
    minimum_participants: int = 3
    status: str = "lobby"
    created_at: float = field(default_factory=time.time)
    started_at: float | None = None
    members: dict[str, FriendsGDMember] = field(default_factory=dict)
    transcript: list[dict[str, Any]] = field(default_factory=list)


class FriendsGDRoomStore:
    def __init__(self, wallets: RewardWalletStore) -> None:
        self._rooms: dict[str, FriendsGDRoom] = {}
        self._code_index: dict[str, str] = {}
        self._lock = threading.RLock()
        self.wallets = wallets

    def _new_code(self) -> str:
        alphabet = string.ascii_uppercase + string.digits
        while True:
            code = "".join(random.SystemRandom().choice(alphabet) for _ in range(6))
            if code not in self._code_index:
                return code

    def create(
        self, user_id: str, name: str, topic: str, mode: str, duration: int,
        maximum: int, minimum: int = 3,
    ) -> FriendsGDRoom:
        with self._lock:
            room = FriendsGDRoom(
                str(uuid.uuid4()), self._new_code(), topic, mode, duration,
                maximum, user_id, minimum_participants=minimum,
            )
            room.members[user_id] = FriendsGDMember(user_id, name, is_host=True, ready=True)
            self._rooms[room.id] = room
            self._code_index[room.code] = room.id
            return room

    def by_code(self, code: str) -> FriendsGDRoom | None:
        with self._lock:
            room_id = self._code_index.get(code.upper())
            return self._rooms.get(room_id) if room_id else None

    def get_for_member(self, room_id: str, user_id: str) -> FriendsGDRoom | None:
        with self._lock:
            room = self._rooms.get(room_id)
            return room if room and user_id in room.members else None

    def join(self, code: str, user_id: str, name: str) -> FriendsGDRoom:
        with self._lock:
            room = self.by_code(code)
            if room is None:
                raise KeyError("room not found")
            if room.status != "lobby":
                raise RuntimeError("discussion has already started")
            if user_id not in room.members and len(room.members) >= room.max_participants:
                raise OverflowError("room is full")
            room.members.setdefault(user_id, FriendsGDMember(user_id, name))
            return room

    def set_ready(self, room: FriendsGDRoom, user_id: str, ready: bool) -> None:
        with self._lock:
            if room.status != "lobby":
                raise RuntimeError("room is not in lobby")
            room.members[user_id].ready = ready

    def start(self, room: FriendsGDRoom, user_id: str) -> None:
        with self._lock:
            if room.host_user_id != user_id:
                raise PermissionError("only the host can start")
            if len(room.members) < room.minimum_participants:
                raise ValueError(f"at least {room.minimum_participants} participants are required")
            if not all(member.ready for member in room.members.values()):
                raise RuntimeError("everyone must be ready")
            room.status = "live"
            room.started_at = time.time()

    @staticmethod
    def score_contribution(room: FriendsGDRoom, text: str) -> tuple[int, list[str]]:
        lowered = text.lower()
        words = re.findall(r"[a-zA-Z][a-zA-Z'-]*", lowered)
        word_count = len(words)
        topic_words = {
            word.lower() for word in re.findall(r"[A-Za-z]{4,}", room.topic)
            if word.lower() not in {"should", "would", "could", "with", "from", "that", "this"}
        }
        hits = len(topic_words.intersection(words))
        score = min(30, word_count) + min(18, hits * 6)
        signals: list[str] = []
        groups = {
            "reasoning": ("because", "therefore", "however", "although", "trade-off", "means that"),
            "evidence": ("data", "evidence", "study", "example", "survey", "percent", "%"),
            "collaboration": ("agree", "building on", "your point", "common ground", "disagree"),
            "solution": ("solution", "recommend", "safeguard", "implement", "measure", "policy"),
        }
        for label, phrases in groups.items():
            if any(phrase in lowered for phrase in phrases):
                score += 10
                signals.append(label)
        if "?" in text:
            score += 5
            signals.append("question")
        prior_texts = [entry["text"].lower() for entry in room.transcript[-8:]]
        if prior_texts and any(lowered == previous for previous in prior_texts):
            score -= 25
        score = max(5, min(100, score))
        return score, signals

    def contribute(self, room: FriendsGDRoom, user_id: str, text: str) -> dict[str, Any]:
        with self._lock:
            self._finish_if_expired(room)
            if room.status != "live":
                raise RuntimeError("discussion is not live")
            score, signals = self.score_contribution(room, text)
            member = room.members[user_id]
            xp = 10 + score // 5
            coins = max(1, score // 20)
            entry = {
                "id": str(uuid.uuid4()), "speaker_id": user_id, "speaker": member.name,
                "text": text, "score": score, "xp": xp, "coins": coins,
                "signals": signals, "created_at": time.time(),
            }
            room.transcript.append(entry)
            member.points += score
            member.xp_earned += xp
            member.coins_earned += coins
            member.contribution_count += 1
            self.wallets.grant(user_id, xp=xp, coins=coins, event_id=f"friends:{room.id}:{entry['id']}")
            return entry

    def _complete(self, room: FriendsGDRoom) -> None:
        room.status = "completed"
        ranking = sorted(room.members.values(), key=lambda member: member.points, reverse=True)
        bonuses = ((40, 12), (25, 8), (15, 5))
        for index, member in enumerate(ranking[:3]):
            xp, coins = bonuses[index]
            member.xp_earned += xp
            member.coins_earned += coins
            self.wallets.grant(member.user_id, xp=xp, coins=coins, event_id=f"friends:{room.id}:rank:{index}")

    def _finish_if_expired(self, room: FriendsGDRoom) -> None:
        if (
            room.status == "live"
            and room.started_at is not None
            and time.time() - room.started_at >= room.duration_minutes * 60
        ):
            self._complete(room)

    def finish_if_expired(self, room: FriendsGDRoom) -> None:
        with self._lock:
            self._finish_if_expired(room)

    def finish(self, room: FriendsGDRoom, user_id: str) -> None:
        with self._lock:
            if room.host_user_id != user_id:
                raise PermissionError("only the host can finish")
            self._finish_if_expired(room)
            if room.status != "live":
                raise RuntimeError("discussion is not live")
            self._complete(room)

    def snapshot(self, room: FriendsGDRoom, viewer_user_id: str) -> dict[str, Any]:
        with self._lock:
            self._finish_if_expired(room)
        participants = sorted(room.members.values(), key=lambda member: (-member.points, member.name.lower()))
        remaining = room.duration_minutes * 60
        if room.started_at:
            remaining = max(0, remaining - int(time.time() - room.started_at))
        return {
            "room_id": room.id, "room_code": room.code, "topic": room.topic, "mode": room.mode,
            "duration_minutes": room.duration_minutes, "status": room.status,
            "minimum_participants": room.minimum_participants, "max_participants": room.max_participants,
            "viewer_user_id": viewer_user_id, "host_user_id": room.host_user_id,
            "can_start": room.status == "lobby" and len(participants) >= room.minimum_participants and all(p.ready for p in participants),
            "remaining_seconds": remaining,
            "participants": [
                {
                    "user_id": p.user_id, "name": p.name, "is_host": p.is_host, "ready": p.ready,
                    "points": p.points, "xp_earned": p.xp_earned, "coins_earned": p.coins_earned,
                    "contribution_count": p.contribution_count,
                } for p in participants
            ],
            "transcript": list(room.transcript),
        }


MATCHMAKING_TOPICS = (
    "Should AI replace repetitive jobs?",
    "Is a four-day workweek practical for India?",
    "Should companies prioritize skills over degrees?",
    "Can online learning replace classrooms?",
    "Should personal data be treated as private property?",
    "Will automation create more jobs than it removes?",
    "Is competition better than collaboration at work?",
    "Should internships always be paid?",
)


class FriendsGDMatchmaker:
    """Process-local 4-player queue used by the live app server.

    The interface is intentionally storage-agnostic so Redis can replace the
    dictionaries for multi-worker production without changing the mobile API.
    """

    def __init__(self, rooms: FriendsGDRoomStore) -> None:
        self.rooms = rooms
        self._queues: dict[tuple[str, int], list[tuple[str, str]]] = {}
        self._matches: dict[str, str] = {}
        self._open_rooms: dict[tuple[str, int], list[str]] = {}
        self._lock = threading.RLock()

    def enqueue(self, user_id: str, name: str, mode: str, duration: int) -> dict[str, Any]:
        key = (mode, duration)
        with self._lock:
            if user_id in self._matches:
                room = self.rooms.get_for_member(self._matches[user_id], user_id)
                if room:
                    return {"state": "matched", "position": 0, "players_found": len(room.members), "room": self.rooms.snapshot(room, user_id)}
            # Match late arrivals into a compatible live room until it reaches
            # the six-player cap. This keeps time-to-start low at four while
            # still allowing richer 5-6 person discussions.
            open_ids = self._open_rooms.setdefault(key, [])
            for room_id in list(open_ids):
                room = self.rooms._rooms.get(room_id)
                if room is not None:
                    self.rooms.finish_if_expired(room)
                if room is None or room.status != "live" or len(room.members) >= 6:
                    open_ids.remove(room_id)
                    continue
                room.members[user_id] = FriendsGDMember(user_id, name, ready=True)
                self._matches[user_id] = room.id
                if len(room.members) >= 6:
                    open_ids.remove(room_id)
                return {
                    "state": "matched", "position": 0, "players_found": len(room.members),
                    "room": self.rooms.snapshot(room, user_id),
                }
            for queued in self._queues.values():
                queued[:] = [entry for entry in queued if entry[0] != user_id]
            queue = self._queues.setdefault(key, [])
            queue.append((user_id, name))
            if len(queue) >= 4:
                group = queue[:4]
                del queue[:4]
                host_id, host_name = group[0]
                room = self.rooms.create(
                    host_id, host_name, random.SystemRandom().choice(MATCHMAKING_TOPICS),
                    mode, duration, 6, minimum=4,
                )
                for member_id, member_name in group[1:]:
                    self.rooms.join(room.code, member_id, member_name)
                for member in room.members.values():
                    member.ready = True
                    self._matches[member.user_id] = room.id
                self.rooms.start(room, host_id)
                self._open_rooms.setdefault(key, []).append(room.id)
                return {"state": "matched", "position": 0, "players_found": 4, "room": self.rooms.snapshot(room, user_id)}
            return {"state": "waiting", "position": len(queue), "players_found": len(queue), "room": None}

    def status(self, user_id: str) -> dict[str, Any]:
        with self._lock:
            room_id = self._matches.get(user_id)
            if room_id:
                room = self.rooms.get_for_member(room_id, user_id)
                if room:
                    return {"state": "matched", "position": 0, "players_found": len(room.members), "room": self.rooms.snapshot(room, user_id)}
            for queue in self._queues.values():
                for index, (queued_id, _) in enumerate(queue):
                    if queued_id == user_id:
                        return {"state": "waiting", "position": index + 1, "players_found": len(queue), "room": None}
            return {"state": "idle", "position": 0, "players_found": 0, "room": None}

    def cancel(self, user_id: str) -> None:
        with self._lock:
            for queue in self._queues.values():
                queue[:] = [entry for entry in queue if entry[0] != user_id]



reward_wallets = RewardWalletStore()
friends_gd_rooms = FriendsGDRoomStore(reward_wallets)
friends_gd_matchmaker = FriendsGDMatchmaker(friends_gd_rooms)


def grant_session_reward(user_id: str, session_id: str, score: float, mode: str) -> dict[str, Any]:
    """Award a consistent completion reward from every practice mode."""
    normalized = max(0, min(100, int(round(score))))
    return reward_wallets.grant(
        user_id,
        xp=20 + normalized // 4,
        coins=3 + normalized // 20,
        event_id=f"practice:{mode}:{session_id}",
    )
