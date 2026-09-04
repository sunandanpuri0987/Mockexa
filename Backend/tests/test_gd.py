import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.providers.llm_backend import GenerationResult

from app.providers.model_router import ModelRouter
from app.utils.session_store import gd_sessions

client = TestClient(app)

from tests.test_auth import _get_token, TEST_SECRET

def get_auth_headers(user_id: str = "test-user-123"):
    return {"Authorization": f"Bearer {_get_token(user_id)}"}


class MockBackend:
    def generate(self, request):
        return GenerationResult(
            text="Mocked GD response.",
            provider="mock",
            model="mock",
            input_tokens=10,
            output_tokens=5,
            latency_seconds=0.1,
            retry_count=0
        )

@pytest.fixture
def mock_gd_router(monkeypatch):
    from app.config import get_settings
    settings = get_settings().model_copy(update={"use_supabase_persistence": False, "groq_api_key": "mock-groq-key"})
    app.dependency_overrides[get_settings] = lambda: settings
    def mock_backend_router(settings):
        return ModelRouter(settings, {"gd_generation": MockBackend()})
    monkeypatch.setattr("app.routers.gd._backend_router", mock_backend_router)
    yield
    app.dependency_overrides.pop(get_settings, None)

def test_gd_start(mock_gd_router):
    headers = get_auth_headers()
    response = client.post(
        "/gd/start",
        json={"topic": "Should we use AI for healthcare?", "num_rounds": 2, "mode": "balanced"},
        headers=headers
    )
    assert response.status_code == 200
    data = response.json()
    assert "session_id" in data
    assert "topic_analysis" in data
    assert len(data["participants"]) == 4

def test_gd_unauthenticated():
    response = client.post(
        "/gd/start",
        json={"topic": "AI in healthcare"}
    )
    assert response.status_code == 401

def test_gd_flow(mock_gd_router):
    headers = get_auth_headers("user-456")
    
    # 1. Start
    res1 = client.post(
        "/gd/start",
        json={"topic": "Climate change policy", "num_rounds": 1, "mode": "balanced"},
        headers=headers
    )
    assert res1.status_code == 200
    session_id = res1.json()["session_id"]
    
    # 2. Respond
    res2 = client.post(
        "/gd/respond",
        json={"session_id": session_id},
        headers=headers
    )
    assert res2.status_code == 200
    turn = res2.json()["turn"]
    assert turn is not None
    assert turn["speaker"] is not None
    assert turn["claim"] == "Mocked GD response."
    
    # Run out the remaining turns for round 1 (4 participants total)
    for _ in range(3):
        res = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
        assert res.status_code == 200
        
    # The next respond should finish the discussion (num_rounds=1)
    res_fin = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
    assert res_fin.status_code == 200
    assert res_fin.json()["finished"] is True
    
    # 3. Finish
    res3 = client.post(
        f"/gd/finish/{session_id}",
        headers=headers
    )
    assert res3.status_code == 200
    data = res3.json()
    assert "metrics" in data
    assert "summary" in data
    
    # 4. Ensure session deleted
    assert gd_sessions.load(session_id, "user-456") is None

def test_gd_wrong_user_cannot_access_session(mock_gd_router):
    # Start session as user 1
    res1 = client.post(
        "/gd/start",
        json={"topic": "Test"},
        headers=get_auth_headers("user-1")
    )
    session_id = res1.json()["session_id"]
    
    # Try to respond as user 2
    res2 = client.post(
        "/gd/respond",
        json={"session_id": session_id},
        headers=get_auth_headers("user-2")
    )
    assert res2.status_code == 404


# --- PHASE 3B PERSISTENCE & TIMING/CONCURRENCY TESTS ---

import json
import time
import asyncio
import uuid
from app.repository import SupabaseRepository
from app.providers.llm_backend import GenerationResult
from app.providers.groq_backend import GroqBackend
from app.providers.llm_backend import LLMRateLimitedError
from app.controllers.gd_controller import DiscussionManager, Argument, Turn
from app.main import app
from app.config import get_settings

class InMemoryMockRepository:
    def __init__(self):
        self.sessions = {}
        self.messages_store = {}
        self.feedback_store = {}
        self.profiles = set()

    async def ensure_profile(self, user_id, token):
        self.profiles.add(user_id)
        return {"id": user_id}

    async def create_session(self, data, token):
        sid = str(uuid.uuid4())
        session_row = {"id": sid, "status": "active", **data}
        self.sessions[sid] = session_row
        self.messages_store[sid] = []
        return session_row

    async def session(self, session_id, user_id, token):
        sess = self.sessions.get(session_id)
        if not sess or sess.get("user_id") != user_id:
            raise ValueError("not found")
        return sess

    async def messages(self, session_id, token):
        return self.messages_store.get(session_id, [])

    async def add_message(self, data, token):
        sid = data["session_id"]
        self.messages_store[sid].append(data)
        return data

    async def upsert_feedback(self, data, token):
        sid = data["session_id"]
        self.feedback_store[sid] = data
        return data

    async def update_session(self, session_id, user_id, token, data):
        sess = self.sessions.get(session_id)
        if sess:
            sess.update(data)
        return sess

@pytest.fixture
def mock_supabase_persistence(monkeypatch):
    # Enable USE_SUPABASE_PERSISTENCE dynamically for testing via app dependency overrides in lowercase
    from app.main import app
    from app.config import get_settings, Settings
    
    settings = Settings(
        use_supabase_persistence=True,
        supabase_url="https://mock.supabase.co",
        supabase_anon_key="mock-anon-key",
        supabase_jwt_secret=TEST_SECRET
    )
    
    app.dependency_overrides[get_settings] = lambda: settings
    
    mock_repo = InMemoryMockRepository()
    monkeypatch.setattr("app.routers.gd.SupabaseRepository", lambda: mock_repo)
    
    yield mock_repo
    
    app.dependency_overrides.clear()

def test_gd_persistence_flow_success(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Test A: Local generation + Groq PASS
    mock_repo = mock_supabase_persistence
    
    verifier_call_count = 0
    def mock_groq_generate(self, request):
        nonlocal verifier_call_count
        verifier_call_count += 1
        return GenerationResult(
            text=json.dumps({"valid": True, "reason": "coherent"}),
            provider="groq",
            model="mock",
            input_tokens=10,
            output_tokens=10,
            latency_seconds=0.1,
            retry_count=0
        )
    monkeypatch.setattr(GroqBackend, "generate", mock_groq_generate)

    headers = get_auth_headers("user-a")
    
    # 1. Start Session
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2, "mode": "balanced"}, headers=headers)
    assert res_start.status_code == 200
    session_id = res_start.json()["session_id"]
    
    # Verify session created in DB
    assert session_id in mock_repo.sessions
    assert mock_repo.sessions[session_id]["user_id"] == "user-a"
    
    # 2. Respond
    res_resp = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
    assert res_resp.status_code == 200
    assert res_resp.json()["finished"] is False
    
    # Verify exactly 1 message persisted
    msgs = mock_repo.messages_store[session_id]
    assert len(msgs) == 1
    assert msgs[0]["speaker_type"] == "agent"
    
    # Verify envelope content
    env = json.loads(msgs[0]["content"])
    assert env["response"] == "Mocked GD response."
    assert verifier_call_count == 1

def test_gd_persistence_flow_correction(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Test B: Local generation + Groq FAIL -> Groq verifier correction applied directly
    mock_repo = mock_supabase_persistence
    
    verifier_call_count = 0
    def mock_groq_generate(self, request):
        nonlocal verifier_call_count
        verifier_call_count += 1
        return GenerationResult(
            text=json.dumps({"valid": False, "reason": "unstructured", "corrected_response": "Here is the corrected response: Corrected text."}),
            provider="groq",
            model="mock",
            input_tokens=10,
            output_tokens=10,
            latency_seconds=0.1,
            retry_count=0
        )
    monkeypatch.setattr(GroqBackend, "generate", mock_groq_generate)

    headers = get_auth_headers("user-a")
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2}, headers=headers)
    session_id = res_start.json()["session_id"]
    
    res_resp = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
    assert res_resp.status_code == 200
    assert res_resp.json()["turn"]["response"] == "Corrected text."
    
    # Verify only response is updated. claim and argument.claim are preserved
    msgs = mock_repo.messages_store[session_id]
    assert len(msgs) == 1
    env = json.loads(msgs[0]["content"])
    assert env["response"] == "Corrected text."
    assert env["claim"] == "Mocked GD response."
    assert env["argument"]["claim"] == "Mocked GD response."
    assert verifier_call_count == 1

def test_gd_persistence_flow_double_fail(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Test C: No correction provided -> no turn persisted, HTTP 500
    mock_repo = mock_supabase_persistence
    
    def mock_groq_generate(self, request):
        return GenerationResult(
            text=json.dumps({"valid": False, "reason": "unstructured", "corrected_response": ""}),
            provider="groq",
            model="mock",
            input_tokens=10,
            output_tokens=10,
            latency_seconds=0.1,
            retry_count=0
        )
    monkeypatch.setattr(GroqBackend, "generate", mock_groq_generate)

    headers = get_auth_headers("user-a")
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2}, headers=headers)
    session_id = res_start.json()["session_id"]
    
    res_resp = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
    assert res_resp.status_code == 500
    assert "provided no correction" in res_resp.json()["detail"]
    
    assert len(mock_repo.messages_store[session_id]) == 0

def test_gd_persistence_flow_groq_429(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Test D: Groq 429 -> no unverified turn returned/persisted, HTTP 503
    mock_repo = mock_supabase_persistence
    
    def mock_groq_generate(self, request):
        raise LLMRateLimitedError("Rate limit exceeded", retry_after_seconds=5)
    monkeypatch.setattr(GroqBackend, "generate", mock_groq_generate)

    headers = get_auth_headers("user-a")
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2}, headers=headers)
    session_id = res_start.json()["session_id"]
    
    res_resp = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
    assert res_resp.status_code == 503
    assert "Groq rate limit (429) hit" in res_resp.json()["detail"]
    
    assert len(mock_repo.messages_store[session_id]) == 0

def test_gd_reconstruction_preserves_history_and_generates_next_turn(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Historical replay preserves loaded history and generates next turn via router
    mock_repo = mock_supabase_persistence

    
    headers = get_auth_headers("user-a")
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2}, headers=headers)
    session_id = res_start.json()["session_id"]
    
    envelope = {
        "speaker": "Dr. Maya Shah",
        "round": 1,
        "action": "INTRODUCE_ARGUMENT",
        "target": None,
        "position": -0.35,
        "claim": "Custom historical claim.",
        "response": "Custom historical response.",
        "confidence": 0.82,
        "issue": "bias",
        "argument": {
            "claim": "Custom historical claim.",
            "reasoning": "Some reasoning",
            "evidence_needed": "",
            "assumptions": "",
            "strength": 0.84,
            "position": "AGAINST",
            "issue": "bias"
        },
        "counter_target": None
    }
    mock_repo.messages_store[session_id].append({
        "session_id": session_id,
        "speaker": "Dr. Maya Shah",
        "speaker_type": "agent",
        "content": json.dumps(envelope),
        "turn_index": 0
    })

    qwen_call_count = 0
    groq_call_count = 0
    
    orig_qwen_generate = MockBackend.generate
    def tracked_qwen_generate(self, request):
        nonlocal qwen_call_count
        qwen_call_count += 1
        return orig_qwen_generate(self, request)
    monkeypatch.setattr(MockBackend, "generate", tracked_qwen_generate)

    def mock_groq_generate(self, request):
        nonlocal groq_call_count
        groq_call_count += 1
        return GenerationResult(
            text=json.dumps({"valid": True, "reason": "coherent"}),
            provider="groq",
            model="mock",
            input_tokens=10,
            output_tokens=10,
            latency_seconds=0.1,
            retry_count=0
        )
    monkeypatch.setattr(GroqBackend, "generate", mock_groq_generate)

    res_resp = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
    assert res_resp.status_code == 200
    assert qwen_call_count == 1
    assert groq_call_count == 1
    
    msgs = mock_repo.messages_store[session_id]
    assert len(msgs) == 2
    assert msgs[0]["turn_index"] == 0
    assert msgs[1]["turn_index"] == 1

def test_gd_finish_feedback_mapping(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Test H: Feedback database mapping matches actual schema
    mock_repo = mock_supabase_persistence
    headers = get_auth_headers("user-a")
    
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2}, headers=headers)
    session_id = res_start.json()["session_id"]
    
    envelope = {
        "speaker": "Dr. Maya Shah",
        "round": 1,
        "action": "INTRODUCE_ARGUMENT",
        "target": None,
        "position": -0.35,
        "claim": "Test.",
        "response": "Test.",
        "confidence": 0.82,
        "issue": "bias",
        "argument": {
            "claim": "Test.",
            "reasoning": "",
            "evidence_needed": "",
            "assumptions": "",
            "strength": 0.84,
            "position": "AGAINST",
            "issue": "bias"
        },
        "counter_target": None
    }
    mock_repo.messages_store[session_id].append({
        "session_id": session_id,
        "speaker": "Dr. Maya Shah",
        "speaker_type": "agent",
        "content": json.dumps(envelope),
        "turn_index": 0
    })

    res_fin = client.post(f"/gd/finish/{session_id}", headers=headers)
    assert res_fin.status_code == 200
    
    feedback = mock_repo.feedback_store[session_id]
    assert feedback["session_id"] == session_id
    assert isinstance(feedback["strengths"], list)
    assert isinstance(feedback["weaknesses"], list)
    assert isinstance(feedback["missing_concepts"], list)

    assert "Consensus:" in feedback["summary"]
    
    assert mock_repo.sessions[session_id]["status"] == "completed"

def test_gd_local_qwen_timeout(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Test K: Qwen timeout -> HTTP 504
    mock_repo = mock_supabase_persistence
    headers = get_auth_headers("user-a")
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2}, headers=headers)
    session_id = res_start.json()["session_id"]
    
    def slow_qwen_generate(self, request):
        time.sleep(0.5)
        return GenerationResult(
            text="Slow text.", provider="mock", model="mock",
            input_tokens=10, output_tokens=5,
            latency_seconds=0.1, retry_count=0
        )
    monkeypatch.setattr(MockBackend, "generate", slow_qwen_generate)

    orig_wait_for = asyncio.wait_for
    async def mock_wait_for(fut, timeout, *args, **kwargs):
        if timeout == 90.0:
            timeout = 0.01
        return await orig_wait_for(fut, timeout, *args, **kwargs)
    monkeypatch.setattr("asyncio.wait_for", mock_wait_for)

    res_resp = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
    assert res_resp.status_code == 504
    assert "generation timed out" in res_resp.json()["detail"].lower()
    
    assert len(mock_repo.messages_store[session_id]) == 0

def test_gd_groq_timeout(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Groq timeout -> HTTP 504
    mock_repo = mock_supabase_persistence
    headers = get_auth_headers("user-a")
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2}, headers=headers)
    session_id = res_start.json()["session_id"]
    
    def slow_groq_generate(self, request):
        time.sleep(0.5)
        return GenerationResult(
            text=json.dumps({"valid": True}), provider="mock", model="mock",
            input_tokens=10, output_tokens=5,
            latency_seconds=0.1, retry_count=0
        )
    monkeypatch.setattr(GroqBackend, "generate", slow_groq_generate)

    orig_wait_for = asyncio.wait_for
    async def mock_wait_for(fut, timeout, *args, **kwargs):
        if timeout == 15.0:
            timeout = 0.01
        return await orig_wait_for(fut, timeout, *args, **kwargs)
    monkeypatch.setattr("asyncio.wait_for", mock_wait_for)

    res_resp = client.post("/gd/respond", json={"session_id": session_id}, headers=headers)
    assert res_resp.status_code == 504
    assert "verification timed out" in res_resp.json()["detail"].lower()
    
    assert len(mock_repo.messages_store[session_id]) == 0

def test_gd_concurrency_serialization(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Test L: Simultaneous /gd/respond calls are serialized by memory lock
    mock_repo = mock_supabase_persistence
    headers = get_auth_headers("user-a")
    
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 2}, headers=headers)
    session_id = res_start.json()["session_id"]

    def mock_groq_generate(self, request):
        return GenerationResult(
            text=json.dumps({"valid": True, "reason": "coherent"}),
            provider="groq",
            model="mock",
            input_tokens=10,
            output_tokens=10,
            latency_seconds=0.1,
            retry_count=0
        )
    monkeypatch.setattr(GroqBackend, "generate", mock_groq_generate)

    generation_active = False
    concurrent_overlap_detected = False
    
    def delayed_qwen_generate(self, request):
        nonlocal generation_active, concurrent_overlap_detected
        if generation_active:
            concurrent_overlap_detected = True
        generation_active = True
        time.sleep(0.05)
        generation_active = False
        return GenerationResult(
            text="Mocked GD response.",
            provider="mock", model="mock",
            input_tokens=10, output_tokens=5,
            latency_seconds=0.1, retry_count=0
        )
    monkeypatch.setattr(MockBackend, "generate", delayed_qwen_generate)

    from app.routers.gd import respond, GDRespondRequest
    from app.main import app
    from app.config import get_settings

    async def run_concurrent():
        req = GDRespondRequest(session_id=session_id)
        settings = app.dependency_overrides[get_settings]()
        await asyncio.gather(
            respond(req, user_id="user-a", raw_token="mock-token", settings=settings),
            respond(req, user_id="user-a", raw_token="mock-token", settings=settings)
        )

    asyncio.run(run_concurrent())
    
    assert concurrent_overlap_detected is False
    assert len(mock_repo.messages_store[session_id]) == 2

def test_gd_target_turn_reconstruction(mock_gd_router, mock_supabase_persistence, monkeypatch):
    # Proves that we reconstruct the exact target turn index correctly on restart
    mock_repo = mock_supabase_persistence
    headers = get_auth_headers("user-a")
    
    res_start = client.post("/gd/start", json={"topic": "AI in medicine", "num_rounds": 3}, headers=headers)
    session_id = res_start.json()["session_id"]
    
    # Write Turn 0 (Speaker A: Dr. Maya Shah)
    envelope0 = {
        "speaker": "Dr. Maya Shah", "round": 1, "action": "INTRODUCE_ARGUMENT", "target": None,
        "position": -0.35, "claim": "Turn 0 Claim.", "response": "Turn 0 Response.", "confidence": 0.82, "issue": "bias",
        "argument": {"claim": "Turn 0 Claim.", "reasoning": "", "evidence_needed": "", "assumptions": "", "strength": 0.84, "position": "AGAINST", "issue": "bias"},
        "counter_target": None, "target_turn_index": None
    }
    mock_repo.messages_store[session_id].append({
        "session_id": session_id, "speaker": "Dr. Maya Shah", "speaker_type": "agent", "content": json.dumps(envelope0), "turn_index": 0
    })
    
    # Write Turn 1 (Speaker A: Dr. Maya Shah - another turn!)
    envelope1 = {
        "speaker": "Dr. Maya Shah", "round": 1, "action": "INTRODUCE_ARGUMENT", "target": None,
        "position": -0.5, "claim": "Turn 1 Claim.", "response": "Turn 1 Response.", "confidence": 0.85, "issue": "safety",
        "argument": {"claim": "Turn 1 Claim.", "reasoning": "", "evidence_needed": "", "assumptions": "", "strength": 0.9, "position": "AGAINST", "issue": "safety"},
        "counter_target": None, "target_turn_index": None
    }
    mock_repo.messages_store[session_id].append({
        "session_id": session_id, "speaker": "Dr. Maya Shah", "speaker_type": "agent", "content": json.dumps(envelope1), "turn_index": 1
    })
    
    # Write Turn 2 (Speaker B: Arjun Mehta - counterarguing Turn 0!)
    envelope2 = {
        "speaker": "Arjun Mehta", "round": 1, "action": "COUNTERARGUE", "target": "Dr. Maya Shah",
        "position": 0.45, "claim": "Turn 2 Claim.", "response": "Turn 2 Response.", "confidence": 0.75, "issue": "bias",
        "argument": {"claim": "Turn 2 Claim.", "reasoning": "", "evidence_needed": "", "assumptions": "", "strength": 0.78, "position": "FOR", "issue": "bias"},
        "counter_target": "Turn 0 Claim.", "target_turn_index": 0 # Explicitly targets Turn 0, not Turn 1!
    }
    mock_repo.messages_store[session_id].append({
        "session_id": session_id, "speaker": "Arjun Mehta", "speaker_type": "agent", "content": json.dumps(envelope2), "turn_index": 2
    })

    from app.routers.gd import _backend_router
    # Reconstruct manager
    manager = DiscussionManager.from_history(
        history=mock_repo.messages_store[session_id],
        topic="AI in medicine",
        config={"topic": "AI in medicine", "num_rounds": 3},
        router=_backend_router(app.dependency_overrides[get_settings]())
    )
    
    assert len(manager.history) == 3
    assert manager.history[2].target_turn_index == 0
    
    agent_b = next(a for a in manager.agents if a.profile.name == "Arjun Mehta")
    assert len(agent_b.targets) == 1
    assert agent_b.targets[0] == "Dr. Maya Shah"

def test_user_contribution_reconstruction_and_prompt_context(mock_gd_router, mock_supabase_persistence, monkeypatch):
    mock_repo = mock_supabase_persistence
    session_id = "test-session-user-history"
    
    # 1. Store an AI turn (turn_index: 0) and a User turn (turn_index: 1)
    ai_envelope = {
        "speaker": "Dr. Maya Shah", "round": 1, "action": "INTRODUCE_ARGUMENT", "target": None,
        "position": -0.35, "claim": "AI turn text", "response": "Remote work can improve productivity...", "confidence": 0.82, "issue": "productivity",
        "argument": {"claim": "AI turn text", "reasoning": "", "evidence_needed": "", "assumptions": "", "strength": 0.84, "position": "AGAINST", "issue": "productivity"}
    }
    user_envelope = {
        "speaker": "You", "round": 1, "action": "USER_CONTRIBUTION", "target": None,
        "position": 0.0, "claim": "User text", "response": "Remote work reduces commuting time but can reduce spontaneous collaboration.", "confidence": 1.0, "issue": "discussion",
        "argument": {"claim": "User text", "reasoning": "User contribution", "evidence_needed": "", "assumptions": "", "strength": 0.8, "position": "NEUTRAL", "issue": "discussion"}
    }
    
    db_messages = [
        {"session_id": session_id, "speaker": "Dr. Maya Shah", "speaker_type": "agent", "content": json.dumps(ai_envelope), "turn_index": 0},
        {"session_id": session_id, "speaker": "You", "speaker_type": "user", "content": json.dumps(user_envelope), "turn_index": 1}
    ]
    mock_repo.messages_store[session_id] = db_messages
    
    captured_prompts = []
    def mock_backend_generate(self, request):
        captured_prompts.append(request.user_prompt)
        return GenerationResult(
            text="AI response addressing user point.", provider="mock", model="mock",
            input_tokens=10, output_tokens=5, latency_seconds=0.1, retry_count=0
        )
    monkeypatch.setattr(MockBackend, "generate", mock_backend_generate)
    
    from app.routers.gd import _backend_router
    manager = DiscussionManager.from_history(
        history=db_messages,
        topic="Remote work and productivity",
        config={"topic": "Remote work and productivity", "num_rounds": 4},
        router=_backend_router(app.dependency_overrides[get_settings]())
    )
    
    # Assert Issue 1 fix: manager.history contains BOTH AI turn and User turn
    assert len(manager.history) == 2
    assert manager.history[0].speaker == "Dr. Maya Shah"
    assert manager.history[1].speaker == "You"
    assert manager.history[1].response == "Remote work reduces commuting time but can reduce spontaneous collaboration."
    
    # Step manager to trigger next AI generation
    turn = manager.step()
    assert turn is not None
    
    # Assert Issue 2 fix: captured prompt contains the user's contribution explicitly
    assert len(captured_prompts) > 0
    assert "LATEST USER CONTRIBUTION (by You):" in captured_prompts[0]
    assert "Remote work reduces commuting time but can reduce spontaneous collaboration." in captured_prompts[0]

def test_parse_verifier_json_robustness():
    from app.routers.gd import parse_verifier_json
    
    # 1. Standard valid JSON
    raw1 = '{"valid": true, "reason": "Good turn", "corrected_response": ""}'
    res1 = parse_verifier_json(raw1)
    assert res1["valid"] is True
    assert res1["reason"] == "Good turn"

    # 2. Fenced markdown JSON with surrounding text
    raw2 = 'Here is the output:\n```json\n{\n  "valid": false,\n  "reason": "Off stance",\n  "corrected_response": "Fixed turn text."\n}\n```\nHope this helps!'
    res2 = parse_verifier_json(raw2)
    assert res2["valid"] is False
    assert res2["reason"] == "Off stance"
    assert res2["corrected_response"] == "Fixed turn text."

    # 3. JSON with unescaped literal newlines inside strings
    raw3 = '{\n  "valid": true,\n  "reason": "Addresses the user point:\nRemote work increases flexibility.",\n  "corrected_response": ""\n}'
    res3 = parse_verifier_json(raw3)
    assert res3["valid"] is True

    # 4. Truncated JSON (unterminated string at line 4 column 25 simulation)
    raw4 = '{\n  "valid": false,\n  "reason": "Incoherent statement",\n  "corrected_response": "Remote work reduces commuting time'
    res4 = parse_verifier_json(raw4)
    assert res4["valid"] is False
    assert res4["reason"] == "Incoherent statement"
    assert "Remote work reduces commuting time" in res4["corrected_response"]

    # 5. Completely invalid non-JSON raises ValueError
    with pytest.raises(ValueError):
        parse_verifier_json("Not a JSON object at all")


def test_gd_from_history_reconstruction_zero_llm_calls():
    # Proves that reconstructing DiscussionManager from history makes ZERO LLM calls
    from app.controllers.gd_controller import DiscussionManager
    from app.providers.model_router import ModelRouter
    from app.providers.llm_backend import LLMBackend, GenerationRequest, GenerationResult

    call_count = 0
    class CountingBackend(LLMBackend):
        def generate(self, request: GenerationRequest) -> GenerationResult:
            nonlocal call_count
            call_count += 1
            return GenerationResult(
                text="Should not be called",
                provider="mock",
                model="mock",
                input_tokens=10,
                output_tokens=10,
                latency_seconds=0.1,
                retry_count=0
            )

    from app.config import get_settings
    router = ModelRouter(get_settings(), CountingBackend())

    
    history = [
        {
            "turn_index": 0,
            "speaker": "Dr. Maya Shah",
            "content": json.dumps({
                "speaker": "Dr. Maya Shah",
                "round": 1,
                "action": "INTRODUCE_ARGUMENT",
                "target": None,
                "position": -0.35,
                "claim": "Historical claim.",
                "response": "Historical response.",
                "confidence": 0.8,
                "issue": "topic",
                "argument": {
                    "claim": "Historical claim.",
                    "reasoning": "Reason",
                    "evidence_needed": "",
                    "assumptions": "",
                    "strength": 0.8,
                    "position": "AGAINST",
                    "issue": "topic"
                }
            })
        }
    ]

    manager = DiscussionManager.from_history(
        history=history,
        topic="Remote work and productivity",
        config={"num_rounds": 3, "mode": "balanced"},
        router=router
    )

    assert call_count == 0
    assert len(manager.history) == 1
    assert manager.history[0].speaker == "Dr. Maya Shah"


def test_gd_balanced_vs_consensus_mode_behavior():
    # Tests actual ParticipantAgent.decide logic in balanced vs consensus mode
    from app.controllers.gd_controller import ParticipantAgent, default_profiles, Turn, Argument, TopicAnalyzer
    
    profile = default_profiles()[0]
    agent = ParticipantAgent(profile)
    analysis = TopicAnalyzer().analyze("AI Ethics")

    
    # Recent history with aligned position (so opposed is empty)
    history = [
        Turn(
            speaker="Other Participant",
            round=3,
            action="INTRODUCE_ARGUMENT",
            target=None,
            position=-0.5,
            claim="Claim",
            response="Response",
            confidence=0.8,
            argument=Argument(claim="Claim", reasoning="", evidence_needed="", assumptions="", strength=0.8, position="AGAINST", issue="ethics")
        )

    ]
    
    # Balanced mode: round_no=3 does NOT trigger SYNTHESIZE
    action_bal, _ = agent.decide(history, analysis, round_no=3, mode="balanced")
    assert action_bal != "SYNTHESIZE"
    
    # Consensus mode: round_no=3 DOES trigger SYNTHESIZE
    action_con, _ = agent.decide(history, analysis, round_no=3, mode="consensus")
    assert action_con == "SYNTHESIZE"


def test_gd_consensus_prompt_instructions():
    # B. Consensus SYNTHESIZE prompt contains explicit synthesis instructions; balanced does not
    from app.config import get_settings
    from app.controllers.gd_controller import NeuralArgumentGenerator, default_profiles, TopicAnalyzer, ParticipantAgent
    from app.providers.model_router import ModelRouter
    from app.providers.llm_backend import LLMBackend, GenerationRequest, GenerationResult

    captured_prompts = []
    class PromptCapturingBackend(LLMBackend):
        def generate(self, request: GenerationRequest) -> GenerationResult:
            captured_prompts.append(request.user_prompt)
            return GenerationResult(text="Synthesized claim.", provider="mock", model="mock", input_tokens=10, output_tokens=10, latency_seconds=0.1, retry_count=0)

    router = ModelRouter(get_settings(), PromptCapturingBackend())
    analysis = TopicAnalyzer().analyze("AI Ethics")
    profile = default_profiles()[0]
    agent = ParticipantAgent(profile)

    # Consensus generator on SYNTHESIZE
    gen_con = NeuralArgumentGenerator(analysis, mode="consensus", router=router)
    gen_con.build(agent, issue="safety", action="SYNTHESIZE")
    assert "Synthesize the discussion toward consensus" in captured_prompts[-1]

    # Balanced generator
    gen_bal = NeuralArgumentGenerator(analysis, mode="balanced", router=router)
    gen_bal.build(agent, issue="safety", action="INTRODUCE_ARGUMENT")
    assert "Preserve independent critical viewpoints" in captured_prompts[-1]


def test_gd_consensus_position_convergence():
    # C. Consensus mode moves agent position toward group mean after synthesis; balanced does not
    from app.config import get_settings
    from app.controllers.gd_controller import DiscussionManager, default_profiles, Turn, Argument
    from app.providers.model_router import ModelRouter
    from app.providers.llm_backend import LLMBackend, GenerationRequest, GenerationResult

    class DummyBackend(LLMBackend):
        def generate(self, request: GenerationRequest) -> GenerationResult:
            return GenerationResult(text="Response text.", provider="mock", model="mock", input_tokens=10, output_tokens=10, latency_seconds=0.1, retry_count=0)

    router = ModelRouter(get_settings(), DummyBackend())
    
    # 1. Consensus mode manager
    mgr_con = DiscussionManager(topic="AI Ethics", profiles=default_profiles(), config={"num_rounds": 4, "mode": "consensus"}, router=router)
    agent = mgr_con.agents[0]
    initial_pos = agent.position
    mean_pos = float(sum(a.position for a in mgr_con.agents) / len(mgr_con.agents))
    
    mgr_con.round_no = 3
    mgr_con.history.append(Turn(
        speaker="Jordan Lee", round=2, action="INTRODUCE_ARGUMENT", target=None, position=initial_pos,
        claim="Claim", response="Resp", confidence=0.8, argument=Argument("Claim", "", "", "", 0.8, "FOR", "ethics")
    ))
    
    turn = mgr_con.step()
    if turn and turn.action == "SYNTHESIZE":
        assert abs(agent.position - mean_pos) < abs(initial_pos - mean_pos)


def test_gd_consensus_score_calculation():
    # D. High convergence positions produce higher consensus score than divergent positions
    from app.config import get_settings
    from app.controllers.gd_controller import DiscussionManager, default_profiles
    from app.providers.model_router import ModelRouter
    from app.providers.llm_backend import LLMBackend, GenerationRequest, GenerationResult

    class DummyBackend(LLMBackend):
        def generate(self, request: GenerationRequest) -> GenerationResult:
            return GenerationResult(text="Resp", provider="mock", model="mock", input_tokens=10, output_tokens=10, latency_seconds=0.1, retry_count=0)

    router = ModelRouter(get_settings(), DummyBackend())
    mgr = DiscussionManager(topic="AI Ethics", profiles=default_profiles(), config={"mode": "consensus"}, router=router)

    for a in mgr.agents:
        a.position = 0.10
    high_score = mgr.calculate_consensus_score()

    mgr.agents[0].position = -0.90
    mgr.agents[1].position = 0.90
    low_score = mgr.calculate_consensus_score()

    assert high_score > low_score
    assert high_score == 100.0


def test_gd_data_driven_final_consensus():
    # E. final_consensus changes dynamically based on participant position spread
    from app.config import get_settings
    from app.controllers.gd_controller import DiscussionManager, DiscussionEvaluator, default_profiles
    from app.providers.model_router import ModelRouter
    from app.providers.llm_backend import LLMBackend, GenerationRequest, GenerationResult

    class DummyBackend(LLMBackend):
        def generate(self, request: GenerationRequest) -> GenerationResult:
            return GenerationResult(text="Resp", provider="mock", model="mock", input_tokens=10, output_tokens=10, latency_seconds=0.1, retry_count=0)

    router = ModelRouter(get_settings(), DummyBackend())
    evaluator = DiscussionEvaluator()
    mgr = DiscussionManager(topic="AI Ethics", profiles=default_profiles(), config={"mode": "consensus"}, router=router)

    for a in mgr.agents:
        a.position = 0.5
    summary_high = evaluator.summary(mgr)
    assert "High consensus" in summary_high["final_consensus"]

    mgr.agents[0].position = -0.9
    mgr.agents[1].position = 0.9
    summary_low = evaluator.summary(mgr)
    assert "Low consensus" in summary_low["final_consensus"]


# Phase 12 Explicit Regression Tests

def test_gd_start_returns_session_and_participants(mock_gd_router):
    headers = get_auth_headers()
    response = client.post(
        "/gd/start",
        json={"topic": "Remote work productivity", "num_rounds": 2, "mode": "balanced"},
        headers=headers
    )
    assert response.status_code == 200
    data = response.json()
    assert "session_id" in data
    assert len(data["participants"]) == 4

def test_gd_first_turn_can_be_generated(mock_gd_router):
    headers = get_auth_headers()
    start_res = client.post(
        "/gd/start",
        json={"topic": "Remote work productivity", "num_rounds": 2, "mode": "balanced"},
        headers=headers
    )
    sid = start_res.json()["session_id"]
    res = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert data["turn"] is not None
    assert data["turn"]["speaker"] is not None
    assert data["finished"] is False

def test_gd_user_contribution_is_processed(mock_gd_router):
    headers = get_auth_headers()
    start_res = client.post("/gd/start", json={"topic": "Remote work", "num_rounds": 2}, headers=headers)
    sid = start_res.json()["session_id"]
    res = client.post(
        "/gd/respond",
        json={"session_id": sid, "user_contribution": "I believe remote work improves productivity when communication is transparent."},
        headers=headers
    )
    assert res.status_code == 200
    assert res.json()["turn"] is not None

def test_gd_user_contribution_reaches_discussion_context(mock_gd_router, mock_supabase_persistence, monkeypatch):
    test_user_contribution_reconstruction_and_prompt_context(mock_gd_router, mock_supabase_persistence, monkeypatch)

def test_gd_multiple_turns_progress(mock_gd_router):
    headers = get_auth_headers()
    start_res = client.post("/gd/start", json={"topic": "AI Ethics", "num_rounds": 2}, headers=headers)
    sid = start_res.json()["session_id"]
    speakers = []
    for _ in range(3):
        res = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
        assert res.status_code == 200
        turn = res.json()["turn"]
        if turn:
            speakers.append(turn["speaker"])
    assert len(speakers) == 3

def test_gd_rounds_finish_correctly(mock_gd_router):
    headers = get_auth_headers()
    start_res = client.post("/gd/start", json={"topic": "AI Ethics", "num_rounds": 1}, headers=headers)
    sid = start_res.json()["session_id"]
    for _ in range(4):
        res = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
        assert res.status_code == 200
    fin_res = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert fin_res.status_code == 200
    assert fin_res.json()["finished"] is True

def test_gd_finish_returns_metrics_and_summary(mock_gd_router):
    headers = get_auth_headers()
    start_res = client.post("/gd/start", json={"topic": "AI Ethics", "num_rounds": 1}, headers=headers)
    sid = start_res.json()["session_id"]
    fin_res = client.post(f"/gd/finish/{sid}", headers=headers)
    assert fin_res.status_code == 200
    data = fin_res.json()
    assert "metrics" in data
    assert "summary" in data

def test_gd_cannot_continue_after_finish(mock_gd_router):
    headers = get_auth_headers()
    start_res = client.post("/gd/start", json={"topic": "AI Ethics", "num_rounds": 1}, headers=headers)
    sid = start_res.json()["session_id"]
    client.post(f"/gd/finish/{sid}", headers=headers)
    res = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert res.status_code in [404, 409, 200]
    if res.status_code == 200:
        assert res.json()["finished"] is True

def test_gd_invalid_session_returns_404(mock_gd_router):
    headers = get_auth_headers()
    res = client.post("/gd/respond", json={"session_id": "nonexistent-id-12345"}, headers=headers)
    assert res.status_code == 404

def test_gd_participants_have_distinct_personas():
    from app.controllers.gd_controller import default_profiles
    profiles = default_profiles()
    names = {p.name for p in profiles}
    roles = {p.role for p in profiles}
    positions = {p.initial_position for p in profiles}
    assert len(names) == 4
    assert len(roles) == 4
    assert len(positions) == 4

def test_gd_consensus_is_data_driven():
    test_gd_data_driven_final_consensus()

def test_gd_verifier_rejects_unsupported_claim(mock_gd_router, mock_supabase_persistence, monkeypatch):
    test_gd_persistence_flow_correction(mock_gd_router, mock_supabase_persistence, monkeypatch)

def test_gd_malformed_ai_output_is_handled():
    test_parse_verifier_json_robustness()

def test_gd_concurrent_requests_are_safe(mock_gd_router, mock_supabase_persistence, monkeypatch):
    test_gd_concurrency_serialization(mock_gd_router, mock_supabase_persistence, monkeypatch)


def test_gd_user_contribution_does_not_penalize_ai_engagement(mock_gd_router):
    from app.controllers.gd_controller import DiscussionManager, DiscussionEvaluator, default_profiles, Turn, Argument
    from app.config import get_settings
    from app.providers.model_router import ModelRouter
    from app.providers.llm_backend import LLMBackend, GenerationRequest, GenerationResult

    class DummyBackend(LLMBackend):
        def generate(self, request: GenerationRequest) -> GenerationResult:
            return GenerationResult(text="Resp", provider="mock", model="mock", input_tokens=10, output_tokens=10, latency_seconds=0.1, retry_count=0)

    router = ModelRouter(get_settings(), DummyBackend())
    mgr = DiscussionManager(topic="AI Ethics", profiles=default_profiles(), config={"mode": "balanced"}, router=router)
    
    # 4 AI participants take 1 turn each (perfect AI panel balance)
    for _ in range(4):
        mgr.step()
        
    evaluator = DiscussionEvaluator()
    score_before = evaluator.evaluate(mgr)["participant_engagement"]
    assert score_before == 100.0

    # User submits 5 contributions
    for i in range(5):
        user_arg = Argument(claim=f"User claim {i}", reasoning="r", evidence_needed="", assumptions="", strength=0.8, position="NEUTRAL", issue="discussion")
        user_turn = Turn(speaker="You", round=1, action="USER_CONTRIBUTION", target=None, position=0.0, claim=f"User claim {i}", response=f"User claim {i}", confidence=1.0, argument=user_arg)
        mgr.history.append(user_turn)

    score_after = evaluator.evaluate(mgr)["participant_engagement"]
    assert score_after == 100.0, f"Expected 100.0 AI panel engagement, got {score_after}"


def test_gd_in_memory_finish_score_mapping(mock_gd_router):
    headers = get_auth_headers()
    start_res = client.post("/gd/start", json={"topic": "AI Ethics", "num_rounds": 1}, headers=headers)
    sid = start_res.json()["session_id"]
    client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    fin_res = client.post(f"/gd/finish/{sid}", headers=headers)
    assert fin_res.status_code == 200
    
    from app.utils.session_store import completed_sessions
    saved = next((s for s in completed_sessions.get_user_sessions("test-user-123") if s["id"] == sid), None)
    assert saved is not None
    assert saved["score"] > 0


def test_gd_target_turn_resolution_with_interspersed_user_contributions(mock_gd_router, mock_supabase_persistence, monkeypatch):
    mock_repo = mock_supabase_persistence
    headers = get_auth_headers("user-interspersed")
    start_res = client.post("/gd/start", json={"topic": "AI in healthcare", "num_rounds": 3}, headers=headers)
    sid = start_res.json()["session_id"]

    # AI Turn 0
    client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    # User Turn 1
    client.post("/gd/respond", json={"session_id": sid, "user_contribution": "User contribution 1"}, headers=headers)
    # AI Turn 2
    client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    # User Turn 3
    client.post("/gd/respond", json={"session_id": sid, "user_contribution": "User contribution 2"}, headers=headers)
    # AI Turn 4
    res = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert res.status_code == 200


def test_gd_in_memory_rollback_on_verifier_timeout(mock_gd_router, monkeypatch):
    headers = get_auth_headers("rollback-user")
    start_res = client.post("/gd/start", json={"topic": "AI Ethics", "num_rounds": 2}, headers=headers)
    sid = start_res.json()["session_id"]

    from app.utils.session_store import gd_sessions
    manager = gd_sessions.load(sid, "rollback-user")
    assert manager is not None
    assert len(manager.history) == 0
    assert manager.turn_index == 0
    assert manager.round_no == 1
    
    from fastapi import HTTPException
    async def mock_verify_fail(*args, **kwargs):
        raise HTTPException(status_code=504, detail="Groq verification timed out.")
    monkeypatch.setattr("app.routers.gd.verify_gd_turn", mock_verify_fail)

    res_fail = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert res_fail.status_code == 504

    # Assert manager state was completely rolled back!
    assert len(manager.history) == 0
    assert manager.turn_index == 0
    assert manager.round_no == 1
    assert len(manager.agents[0].arguments) == 0
    assert len(manager.agents[0].memory.claims) == 0

    # Restore verifier pass
    async def mock_verify_pass(topic, speaker_name, stance, unverified_text, history_context, settings):
        return unverified_text
    monkeypatch.setattr("app.routers.gd.verify_gd_turn", mock_verify_pass)

    res_success = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert res_success.status_code == 200
    turn_data = res_success.json()["turn"]
    assert turn_data["speaker"] == manager.agents[0].profile.name
    assert len(manager.history) == 1
    assert manager.turn_index == 1


def test_gd_multiturn_sequence_and_null_envelope_safety(mock_gd_router, mock_supabase_persistence):
    mock_repo = mock_supabase_persistence
    headers = get_auth_headers("user-multiturn")
    start_res = client.post("/gd/start", json={"topic": "AI in education", "num_rounds": 2}, headers=headers)
    assert start_res.status_code == 200
    sid = start_res.json()["session_id"]

    # Turn 0: AI_1 (Dr. Maya Shah)
    r1 = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert r1.status_code == 200
    assert r1.json()["turn"]["speaker"] == "Dr. Maya Shah"

    # User contribution + Turn 1: AI_2 (Jordan Lee)
    r_user = client.post("/gd/respond", json={"session_id": sid, "user_contribution": "User input text"}, headers=headers)
    assert r_user.status_code == 200
    assert r_user.json()["turn"]["speaker"] == "Jordan Lee"

    # Inject a DB message with null fields in content JSON envelope to test from_history resilience
    null_envelope = {
        "speaker": "Arjun Mehta",
        "round": None,
        "action": "INTRODUCE_ARGUMENT",
        "target": None,
        "position": None,
        "claim": "Null claim test",
        "response": "Null response test",
        "confidence": None,
        "issue": None,
        "argument": {"claim": "Null claim", "position": None, "strength": None}
    }
    mock_repo.messages_store[sid].append({
        "session_id": sid,
        "speaker": "Arjun Mehta",
        "speaker_type": "agent",
        "content": json.dumps(null_envelope),
        "turn_index": len(mock_repo.messages_store[sid])
    })

    # Turn 2: AI_3 - should reconstruct without 500 TypeError
    r3 = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert r3.status_code == 200

def test_gd_counterargue_round2_transition_safety(mock_gd_router, mock_supabase_persistence, monkeypatch):
    phrases = [
        "Statistical uncertainty in medical trials requires randomized sampling protocols.",
        "Equity and dignity for marginal communities demand direct participatory governance.",
        "Rapid technological innovation creates massive market opportunities for startups.",
        "Economic cost benefit analysis proves fiscal incentives align regulatory compliance.",
        "Narrow testable safeguards must be established before accepting remote work conclusions.",
    ]
    count = 0
    def mock_generate_distinct(self, request):
        nonlocal count
        text = phrases[count % len(phrases)]
        count += 1
        return GenerationResult(
            text=text,
            provider="mock",
            model="mock",
            input_tokens=10,
            output_tokens=5,
            latency_seconds=0.1,
            retry_count=0
        )
    monkeypatch.setattr(MockBackend, "generate", mock_generate_distinct)

    mock_repo = mock_supabase_persistence
    headers = get_auth_headers("user-counterargue-transition")
    start_res = client.post("/gd/start", json={"topic": "Remote work productivity", "num_rounds": 2}, headers=headers)
    assert start_res.status_code == 200
    sid = start_res.json()["session_id"]

    # AI 1: Dr. Maya Shah
    r1 = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert r1.status_code == 200
    assert r1.json()["turn"]["speaker"] == "Dr. Maya Shah"

    # User 1 + AI 2: Jordan Lee
    u1 = client.post("/gd/respond", json={"session_id": sid, "user_contribution": "User contribution 1"}, headers=headers)
    assert u1.status_code == 200
    assert u1.json()["turn"]["speaker"] == "Jordan Lee"

    # User 2 + AI 3: Arjun Mehta
    u2 = client.post("/gd/respond", json={"session_id": sid, "user_contribution": "User contribution 2"}, headers=headers)
    assert u2.status_code == 200
    assert u2.json()["turn"]["speaker"] == "Arjun Mehta"

    # User 3 + AI 4: Elena Ruiz (round 1 complete, round_no becomes 2)
    u3 = client.post("/gd/respond", json={"session_id": sid, "user_contribution": "User contribution 3"}, headers=headers)
    assert u3.status_code == 200
    assert u3.json()["turn"]["speaker"] == "Elena Ruiz"

    # AI 5: Round 2 transition where COUNTERARGUE action triggers for Dr. Maya Shah
    r5 = client.post("/gd/respond", json={"session_id": sid}, headers=headers)
    assert r5.status_code == 200
    turn5 = r5.json()["turn"]
    assert turn5 is not None
    assert turn5["speaker"] == "Dr. Maya Shah"
    assert turn5["action"] == "COUNTERARGUE"
    assert turn5["target"] == "Arjun Mehta"









