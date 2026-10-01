# Mockexa Backend

## Overview
FastAPI backend service powering the Mockexa interview preparation platform. Provides REST APIs for:
- **Group Discussion (GD)** multi-speaker AI panel simulations (Gemini & optional local LoRA model router)
- **Technical Interviews** with adaptive topic evaluation and structured feedback
- **HR & Behavioral Interviews** with situational assessment scoring
- **Session Persistence & History** with Supabase PostgreSQL & in-memory session management
- **Supabase Auth** JWT token verification & security middleware

## Quick Start

```bash
cd Backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in GEMINI_API_KEY and SUPABASE credentials
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Interactive API documentation is available at `http://127.0.0.1:8000/docs`.

### Quick Verification

```bash
curl http://127.0.0.1:8000/health

curl -X POST http://127.0.0.1:8000/technical/start \
  -H "Content-Type: application/json" \
  -d '{"name":"Candidate","target_role":"Software Engineer","experience":"Intermediate","selected_domains":["Algorithms"],"max_questions":5}'
```

## Running Tests

```bash
pytest tests/ -v
```

The test suite covers GD generation, Technical evaluation, HR scoring, Auth middleware, Model router fallback, and Session persistence.

## Group Discussion (GD) Model Provider

- **Default Provider**: Group Discussion AI turns run through Gemini (`GD_GENERATION_BACKEND=gemini` in `.env`).
- **Optional Local ML Model**: The codebase supports a local `Qwen2.5-1.5B-Instruct` LoRA adapter (`GD_GENERATION_BACKEND=local`).
- **Model Weight Artifacts**: Heavy binary weights (`group_d/model/adapter_model.safetensors`, ~141 MB) are intentionally **excluded** from Git source control to maintain repository size limits.
- **Local Developer Setup**: Developers who wish to run local CPU/GPU ML inference should obtain `adapter_model.safetensors` separately and place it in `Backend/group_d/model/`.

## Architecture & Layout

```
app/
  main.py                          FastAPI entry point & route registration
  config.py                        Centralized Pydantic settings & environment configuration
  auth.py                          Supabase JWT verification & auth dependencies
  repository.py                    Database operations & Supabase persistence helper
  controllers/
    gd_controller.py               Multi-persona GD speaker turn generation & panel logic
    technical_controller.py        Adaptive technical question & answer evaluator
    hr_controller.py               HR situational question & evaluation engine
  providers/
    llm_backend.py                 LLM protocol definitions & exception handling
    gemini_backend.py                Gemini Cloud SDK integration with retry & token budget
    model_router.py                Dynamic routing between Gemini and local ML models
  routers/
    health.py, gd.py, technical.py, hr.py, sessions.py Active API routes
  schemas/                         Pydantic DTO request and response models
  utils/
    token_budget.py                Prompt token estimation & context window truncation
    session_store.py               Session cache & thread-safe storage
tests/                             Comprehensive test suite
```
