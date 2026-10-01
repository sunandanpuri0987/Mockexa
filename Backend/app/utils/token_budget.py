"""
Rough token estimation and budget enforcement.

This is deliberately a heuristic (chars/4), not a real tokenizer, so it adds
no heavy dependency to the FastAPI process. It is used only to REJECT or
TRUNCATE oversized requests before they're sent — never to bill or report
actual usage (actual usage, where available, comes from the provider
response and is logged separately; see providers/gemini_backend.py).
"""
from __future__ import annotations


def estimate_tokens(text: str) -> int:
    """Conservative estimate: ~4 characters per token for English text.
    Deliberately rounds up so we err on the side of truncating too early
    rather than overshooting a real limit."""
    if not text:
        return 0
    return max(1, (len(text) + 3) // 4)


def enforce_input_budget(text: str, max_input_tokens: int) -> str:
    """Truncate `text` from the front (drop oldest content first) so it fits
    the budget. Never truncates from the end, since the most recent turn /
    the actual instruction is usually appended last and must survive."""
    if estimate_tokens(text) <= max_input_tokens:
        return text
    max_chars = max_input_tokens * 4
    return text[-max_chars:]


def reduce_history_to_budget(turns: list[str], max_input_tokens: int, reserved_tokens: int = 0) -> list[str]:
    """Drop oldest turns first until the remaining joined history fits the
    budget. This is the 'safe truncation' strategy; callers needing a rolling
    summary instead should summarize before calling this."""
    budget = max(0, max_input_tokens - reserved_tokens)
    kept: list[str] = []
    running = 0
    for turn in reversed(turns):
        cost = estimate_tokens(turn)
        if running + cost > budget:
            break
        kept.append(turn)
        running += cost
    kept.reverse()
    return kept
