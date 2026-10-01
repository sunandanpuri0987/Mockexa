# BACKEND_IMPLEMENTATION_PLAN.md (Historical Initial Plan)

> [!NOTE]  
> **Historical Archive**: This document represents the initial phase implementation plan. For the current, fully implemented architecture (including active GD, Technical, HR, and Supabase Persistence endpoints), see [`MOCKEXA_CURRENT_PROJECT.md`](file:///Users/dhruvsoni/Desktop/PrepAI/MOCKEXA_CURRENT_PROJECT.md) and [`Backend/README.md`](file:///Users/dhruvsoni/Desktop/PrepAI/Backend/README.md).

Written after `IMPLEMENTATION_AUDIT_BACKEND.md`. Covers what was originally planned/built in Pass 1.

## What exists now (built and verified this pass)

| Component | File(s) | Status |
|---|---|---|
| FastAPI app, health check | `app/main.py`, `app/routers/health.py` | Built. Live-started as a real process, `curl`'d successfully (§ below). |
| `ModelRouter` (single entrypoint controllers call) | `app/providers/model_router.py` | Built, unit tested (2 tests). |
| `GeminiBackend` (retries/backoff/timeout/429/budget) | `app/providers/gemini_backend.py` | Built, unit tested with the Gemini client mocked (7 tests covering success, budget rejection, transient retry+recover, retry exhaustion, 429, empty-response, non-retryable fast-fail). **Not yet exercised against the live Gemini API** — needs a real `GEMINI_API_KEY` (see Verification section). |
| `LLMBackend` protocol + shared exceptions | `app/providers/llm_backend.py` | Built. |
| Token budget estimation/truncation | `app/utils/token_budget.py` | Built, unit tested (5 tests). Heuristic (chars/4), not a real tokenizer — good enough to enforce budgets, not for billing. |
| Technical Interview controller | `app/controllers/technical_controller.py` | **Ported, not rewritten**, from the tested notebook code (`technical_interview_training_colab_REPAIRED.ipynb`, cell 5). Same classes, same logic. Unit tested here again (5 tests) to confirm the port didn't change behavior. |
| Gemini-backed technical evaluator | `app/controllers/technical_gemini_backend.py` | New. Implements the same `evaluate`/`follow_up` interface as `CuratedTechnicalBackend` so it's a drop-in; relies on `InterviewController`'s existing `StructuredOutputValidator` fallback for safety. **Not yet live-tested against Gemini.** Currently **disabled by default** in the route (`use_gemini=False`) until it is. |
| Technical routes (`/technical/start`, `/answer`, `/finish/{id}`) | `app/routers/technical.py` | Built and **live-verified**: real `uvicorn` process, real `curl` requests, full flow (start → follow-up → answer → completion → report) — see Verification. |
| GD/HR routes | `app/routers/gd.py`, `app/routers/hr.py` | Deliberately stubbed to return `501 Not Implemented` with an explanatory message. No fabricated business logic — see rationale in each file's docstring. |
| In-memory session store | `app/utils/session_store.py` | Placeholder only. Explicitly documented as not production-durable and not enforcing per-user access control — real persistence/auth is Person 3's boundary. |

## Verification actually performed (be precise about what "tested" means here)

**PASS 1 — Static**: `app.main:app` imports cleanly; `app.openapi()` was inspected directly and confirms all 11 expected routes are registered with correct methods/paths.

**PASS 2 — Runtime, CODE PATH VERIFIED (not LIVE Gemini verified)**:
- `pytest` run: **24/24 passed** (token budget, technical controller, GeminiBackend with mocked client, ModelRouter, and full API flow via `TestClient`).
- The FastAPI app was **actually started as a subprocess** (`uvicorn app.main:app`) and hit with **real `curl` HTTP requests**, not just `TestClient`:
  - `GET /health` → `200 {"status":"ok",...}`
  - `POST /technical/start` → real question returned
  - `POST /technical/answer` (x2) → real rubric-scored analysis, a real follow-up question, then completion
  - `POST /technical/finish/{id}` → real report with `overall_score`, `mastery`, `question_log`
  - `POST /gd/start`, `POST /hr/start` → `501` (confirmed honest, not silently succeeding)
  - `GET /docs` → `200`

**What was NOT verified (explicitly, per the audit's "CODE PATH vs LIVE PROVIDER" distinction)**:
- No real Gemini API call was made anywhere — `gemini_configured: false` in the health check throughout, because no `GEMINI_API_KEY` is available in this environment. `GeminiBackend` and `GeminiTechnicalBackend` are code-path-tested with the SDK client mocked, not live-tested.
- No real Supabase/database calls — persistence is an in-memory placeholder.
- No authentication/authorization — every route is currently open; auth boundary is explicitly not built yet (see below).

## Explicitly NOT built in this pass (do not assume these exist)

- GD moderator/`DiscussionManager`, `DiscussionState`, GD analytics, GD persona registry — nothing. Routes 501.
- HR controller, HR question bank, HR evaluation — nothing. Routes 501.
- Feedback aggregation architecture, readiness score computation — nothing yet.
- Authentication/authorization boundary — nothing yet. **Every route above is currently unauthenticated; do not deploy or demo this as-is to anyone outside the dev team without adding auth first.**
- Real persistence (Supabase) — in-memory placeholder only, explicitly marked non-durable.
- `docs/api-contract.yaml` — not written yet; the routes above are the current de facto contract (visible at `/docs`), should be written up formally once GD/HR shapes are decided.

## Immediate next steps, in priority order

1. **Get a real `GEMINI_API_KEY` into an environment with network access to Gemini** and run `GeminiBackend`/`GeminiTechnicalBackend` live at least once (a handful of real requests, checking retry/budget behavior isn't just theoretical). Flip `use_gemini=True` in `app/routers/technical.py` only after that.
2. Decide and build the authentication boundary (coordinate with Person 3 — "never trust arbitrary user_id supplied by client" per PROJECT_STATUS.md). Every route needs this before any real session data flows through it.
3. Once the late GD moderator/`DiscussionManager` upload arrives: build `DiscussionState` + wire it through `ModelRouter` with a `gd_generation` task (already budgeted in `config.py`), replacing `app/routers/gd.py`'s stubs.
4. Build `HRController` following the same controller/backend separation pattern as Technical (this pattern is now proven end-to-end, so HR should be faster to build than Technical was).
5. Replace `InMemorySessionStore` with a real repository once Person 3's Supabase schema exists.
