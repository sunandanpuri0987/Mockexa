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
cp .env.example .env   # fill in Supabase credentials; AI provider keys are optional
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
python -m pytest tests/ -v
```

The test suite covers GD generation, Technical evaluation, HR scoring, Auth middleware, Model router fallback, and Session persistence.

## Cloud deployment

The repository root contains `render.yaml` for a Render Blueprint deployment.
It provisions the FastAPI service with managed HTTPS, installs the lean
production dependency set from `requirements-prod.txt`, starts Uvicorn on
Render's assigned port, and checks `/health` during deploys. Secret values stay
in the Render environment and must never be committed to Git.

## Group Discussion (GD) Model Provider

- **Production Provider**: Group Discussion AI turns run through Gemini.
- **Failure Handling**: The GD controller keeps a deterministic, persona-specific fallback for temporary provider failures.
- **No Local Weights Required**: A fresh checkout does not download or load PyTorch/Qwen model artifacts.

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
    model_router.py                Provider-neutral task routing and token budgets
  routers/
    health.py, gd.py, technical.py, hr.py, sessions.py Active API routes
  schemas/                         Pydantic DTO request and response models
  utils/
    token_budget.py                Prompt token estimation & context window truncation
    session_store.py               Session cache & thread-safe storage
tests/                             Comprehensive test suite
```
