import pytest
from app.controllers.gd_controller import is_meaningless_user_input, DiscussionManager, default_profiles
from app.config import get_settings
from app.providers.llm_backend import GenerationResult, LLMBackend
from app.providers.model_router import ModelRouter


class DeterministicGDBackend(LLMBackend):
    def generate(self, request):
        return GenerationResult(
            text="AI can improve diagnostic consistency, but clinicians must retain oversight for unusual cases.",
            provider="test",
            model="deterministic",
            input_tokens=10,
            output_tokens=15,
            latency_seconds=0.0,
            retry_count=0,
        )

def test_is_meaningless_user_input_cases():
    # True cases (gibberish / random)
    assert is_meaningless_user_input("Kjb...") is True
    assert is_meaningless_user_input("asdf qwer zxcv") is True
    assert is_meaningless_user_input("12345") is True
    assert is_meaningless_user_input("   ") is True
    assert is_meaningless_user_input("") is True
    assert is_meaningless_user_input("zzzzzz") is True

    # False cases (meaningful input)
    assert is_meaningless_user_input("I disagree.") is False
    assert is_meaningless_user_input("Yes.") is False
    assert is_meaningless_user_input("No.") is False
    assert is_meaningless_user_input("This is risky.") is False
    assert is_meaningless_user_input("I agree.") is False
    assert is_meaningless_user_input("Social media improves access to information.") is False
    assert is_meaningless_user_input("I don't think this is practical.") is False

def test_gibberish_input_triggers_clarification():
    settings = get_settings()
    backend = DeterministicGDBackend()
    router = ModelRouter(settings, {"gd_generation": backend, "gd_verification": backend})
    
    profiles = default_profiles()
    config = {"num_rounds": 2, "mode": "balanced", "user_name": "Arjun Mehta"}
    manager = DiscussionManager(
        topic="Should artificial intelligence be used to automate medical diagnoses?",
        profiles=profiles,
        config=config,
        router=router
    )
    
    # Turn 1: AI start turn
    turn1 = manager.step()
    assert turn1 is not None
    
    # Simulate user adding gibberish turn "Kjb..."
    from app.controllers.gd_controller import Turn, Argument
    user_gibberish_turn = Turn(
        speaker="You",
        round=1,
        action="USER_CONTRIBUTION",
        target=None,
        position=0.0,
        claim="Kjb...",
        response="Kjb...",
        confidence=0.5,
        argument=Argument("Kjb...", "", "", "", 0.5, "NEUTRAL", "discussion")
    )
    manager.history.append(user_gibberish_turn)
    
    # Turn 2: Next AI turn after gibberish
    turn2 = manager.step()
    assert turn2 is not None
    
    # Verify AI does NOT attribute a fabricated argument to user, and asks for clarification
    resp_text = turn2.response.lower()
    print(f"AI response after gibberish:\n{turn2.response}")
    assert "clarify" in resp_text or "not sure" in resp_text or "caught" in resp_text or "position" in resp_text
    assert "raises a fair point" not in resp_text
    assert "specificity" not in resp_text
