from app.utils.token_budget import enforce_input_budget, estimate_tokens, reduce_history_to_budget


def test_estimate_tokens_empty():
    assert estimate_tokens("") == 0


def test_estimate_tokens_roughly_scales_with_length():
    assert estimate_tokens("a" * 400) == 100


def test_enforce_input_budget_no_op_when_under_budget():
    text = "short text"
    assert enforce_input_budget(text, max_input_tokens=1000) == text


def test_enforce_input_budget_truncates_from_front():
    text = "OLD" * 2000 + "NEWEST"
    truncated = enforce_input_budget(text, max_input_tokens=10)
    assert truncated.endswith("NEWEST")
    assert len(truncated) <= 40


def test_reduce_history_drops_oldest_first():
    turns = ["turn1 " * 5, "turn2 " * 5, "turn3 " * 5]
    kept = reduce_history_to_budget(turns, max_input_tokens=6)
    assert kept == turns[-1:] or kept == []
    # newest turn is prioritized if anything survives
    if kept:
        assert kept[-1] == turns[-1]
