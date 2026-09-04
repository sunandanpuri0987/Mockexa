from __future__ import annotations
import uuid
import json
import re
import asyncio
import time
import logging

logger = logging.getLogger(__name__)
from contextlib import asynccontextmanager
from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user_id, get_raw_jwt_token, get_user_display_name_from_token
from app.config import Settings, get_settings
from app.schemas.gd import (
    GDStartRequest,
    GDStartResponse,
    GDRespondRequest,
    GDRespondResponse,
    GDFinishResponse,
    GDTurnResponse,
)
from app.controllers.gd_controller import DiscussionManager, default_profiles, DiscussionEvaluator, Argument, Turn
from app.utils.session_store import gd_sessions
from app.providers.model_router import ModelRouter
from app.repository import SupabaseRepository, RepositoryError, NotFoundError
from app.providers.llm_backend import LLMRateLimitedError


router = APIRouter(prefix="/gd", tags=["gd"])

# Process-local reference-counted lock manager to prevent concurrent request corruptions per session_id
class SessionLockManager:
    def __init__(self):
        self._locks = {}
        self._global_lock = asyncio.Lock()

    @asynccontextmanager
    async def lock(self, session_id: str):
        async with self._global_lock:
            if session_id not in self._locks:
                self._locks[session_id] = [asyncio.Lock(), 0]
            lock_entry = self._locks[session_id]
            lock_entry[1] += 1
            
        async with lock_entry[0]:
            yield
            
        async with self._global_lock:
            lock_entry[1] -= 1
            if lock_entry[1] == 0:
                self._locks.pop(session_id, None)

session_locks = SessionLockManager()

def parse_verifier_json(raw_text: str) -> dict:
    cleaned = raw_text.strip()
    
    # 1. Strip markdown code blocks if present
    if "```" in cleaned:
        fence_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", cleaned, re.DOTALL)
        if fence_match:
            cleaned = fence_match.group(1).strip()
        else:
            lines = [line for line in cleaned.splitlines() if not line.strip().startswith("```")]
            cleaned = "\n".join(lines).strip()

    # 2. Extract outer JSON object bounds
    start_idx = cleaned.find("{")
    end_idx = cleaned.rfind("}")
    if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
        cleaned = cleaned[start_idx:end_idx + 1]
    elif start_idx != -1:
        cleaned = cleaned[start_idx:]

    # 3. Direct parse attempt with strict=False (allows unescaped control characters like literal newlines)
    try:
        data = json.loads(cleaned, strict=False)
        if isinstance(data, dict) and "valid" in data:
            return data
    except Exception:
        pass

    # 4. Sanitize literal newlines inside string literals if basic parse failed
    try:
        sanitized = re.sub(
            r'(?<=: ")(.*?)(?=",\s*"\w+":|"\s*\})',
            lambda m: m.group(1).replace('\n', '\\n').replace('\r', ''),
            cleaned,
            flags=re.DOTALL
        )
        data = json.loads(sanitized, strict=False)
        if isinstance(data, dict) and "valid" in data:
            return data
    except Exception:
        pass

    # 5. Robust Regex Extraction fallback for truncated or syntax-damaged LLM JSON
    valid_match = re.search(r'"valid"\s*:\s*(true|false)', cleaned, re.IGNORECASE)
    if valid_match:
        is_valid = valid_match.group(1).lower() == "true"
        
        reason_match = re.search(r'"reason"\s*:\s*"(.*?)(?:"\s*,\s*"|\s*"\s*\}|\s*$)', cleaned, re.DOTALL)
        reason = reason_match.group(1) if reason_match else ""
        
        corrected_match = re.search(r'"corrected_response"\s*:\s*"(.*?)(?:"|\s*$)', cleaned, re.DOTALL)
        corrected = corrected_match.group(1) if corrected_match else ""
        
        return {
            "valid": is_valid,
            "reason": reason.strip(),
            "corrected_response": corrected.strip()
        }

    raise ValueError(f"Unparseable verifier JSON (raw snippet: {raw_text[:150]!r})")

from app.controllers.gd_controller import _clean_response_text

def _clean_corrected_response(text: str, speaker_name: str | None = None) -> str:
    cleaned = text.strip()
    cleaned = re.sub(r'^(?:here\s+is\s+(?:the\s+)?corrected\s+response|corrected\s+response|corrected\s+text)\s*:\s*', '', cleaned, flags=re.IGNORECASE).strip()
    return _clean_response_text(cleaned, speaker_name)

# Helper to verify a generated response text using Groq
async def verify_gd_turn(
    topic: str,
    speaker_name: str,
    stance: float,
    unverified_text: str,
    history_context: str,
    settings: Settings
) -> str:
    if settings.groq_api_key and (settings.groq_api_key.startswith("mock") or "mock" in settings.groq_api_key.lower() or settings.groq_api_key == "test-key"):
        return unverified_text

    verifier_settings = settings.model_copy(update={
        "groq_max_retries": 2,
        "groq_timeout_seconds": 12.0
    })
    
    from app.providers.groq_backend import GroqBackend
    try:
        groq_backend = GroqBackend(verifier_settings)
        groq_router = ModelRouter(verifier_settings, {
            "gd_generation": groq_backend,
            "gd_verification": groq_backend
        })
    except Exception as e:
        if not settings.use_supabase_persistence and ("GROQ_API_KEY" in str(e) or "missing" in str(e).lower()):
            return unverified_text
        raise HTTPException(status_code=503, detail=f"Groq verifier initialization failed: {e}")

    system_prompt = (
        "You are a Group Discussion Verifier. Your task is to analyze the newly generated turn text "
        "for a participant agent in a group discussion.\n"
        "You must verify:\n"
        "1. Topic relevance: Does the text address the topic?\n"
        "2. Coherence and consistency: Is it logically coherent and does it fit the ongoing context?\n"
        "3. Participant alignment: Does the response align with the participant's name and known stance?\n"
        "4. Structure: Is it a natural response, and does it avoid being malformed or hallucinated?\n\n"
        "You must output a structured JSON response matching this schema:\n"
        "{\n"
        "  \"valid\": true/false,\n"
        "  \"reason\": \"brief explanation of decision\",\n"
        "  \"corrected_response\": \"if valid is false, provide a corrected response; if valid is true, output empty string \\\"\\\"\"\n"
        "}\n\n"
        "Ensure the output contains ONLY the valid JSON block. Do not include markdown wraps like ```json."
    )

    user_prompt_template = (
        "TOPIC: {topic}\n"
        "SPEAKER: {speaker}\n"
        "STANCE (STANCE: -1 to 1): {stance:+.2f}\n"
        "RECENT CONTEXT:\n{context}\n"
        "GENERATED RESPONSE TO VERIFY: {response}\n\n"
        "Is this response valid? If not, output corrected_response."
    )

    def run_groq_call(text_to_verify: str) -> tuple[dict, str]:
        user_prompt = user_prompt_template.format(
            topic=topic,
            speaker=speaker_name,
            stance=stance,
            context=history_context,
            response=text_to_verify
        )
        result = groq_router.generate(
            task="gd_verification",
            system_prompt=system_prompt,
            user_prompt=user_prompt
        )
        return parse_verifier_json(result.text), result.text

    unverified_text = _clean_response_text(unverified_text, speaker_name)
    low_text = unverified_text.lower()
    if "clarify" in low_text or "not sure i caught" in low_text or "could you clarify" in low_text:
        logger.info("[GD VERIFIER] Bypassing verification for clarification response: %r", unverified_text)
        return unverified_text

    # First attempt: verify original Qwen output
    try:
        t_ver_start = time.monotonic()
        logger.info("[GD TIMING] verification started for speaker %s", speaker_name)
        data, raw1 = await asyncio.wait_for(
            asyncio.to_thread(run_groq_call, unverified_text),
            timeout=15.0
        )
        logger.info("[GD TIMING] verification completed in %.2fs", time.monotonic() - t_ver_start)
        logger.info("[GD VERIFIER] Call 1 for %s: valid=%s, reason=%r, raw=%r", speaker_name, data.get("valid"), data.get("reason"), raw1)
        if data.get("valid") is True:
            return unverified_text

        # First verification failed, check for correction from Groq
        corrected = data.get("corrected_response")
        logger.info("[GD VERIFIER] Call 1 corrected_response for %s: %r", speaker_name, corrected)
        if corrected and corrected.strip():
            cleaned_corrected = _clean_corrected_response(corrected, speaker_name)
            if cleaned_corrected:
                logger.info("[GD VERIFIER] Applying Groq verifier correction for speaker %s", speaker_name)
                return cleaned_corrected

        raise HTTPException(status_code=500, detail="Groq flagged response as invalid and provided no correction.")

    except LLMRateLimitedError as e:
        raise HTTPException(status_code=503, detail=f"Groq rate limit (429) hit during verification: {e}")
    except HTTPException:
        raise
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Groq verification timed out.")
    except Exception as e:
        if "429" in str(e) or "rate limit" in str(e).lower():
            raise HTTPException(status_code=503, detail="Groq rate limit (429) hit during verification.")
        raise HTTPException(status_code=500, detail=f"Groq verification failed: {e}")

def _backend_router(settings: Settings):
    """Return a ModelRouter wired to the configured GD generation backend.

    GD_GENERATION_BACKEND=groq  (default, current) — uses the existing Groq
        backend via the already-configured GROQ_API_KEY and GROQ_MODEL.
    GD_GENERATION_BACKEND=local — loads the local Qwen LoRA adapter (slow on
        CPU; restore once performance is resolved).
    """
    backend_name = (settings.gd_generation_backend or "groq").lower().strip()

    if backend_name == "local":
        from app.providers.gd_backend import LocalQwenBackend
        from pathlib import Path
        model_dir = Path("group_d/model")
        try:
            local_backend = LocalQwenBackend.get_instance(model_dir=model_dir)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to load GD ML backend: {e}")
        return ModelRouter(settings, {"gd_generation": local_backend})
    else:
        # Default: "groq" — fast, uses existing GROQ_API_KEY + GROQ_MODEL.
        from app.providers.groq_backend import GroqBackend
        try:
            groq_backend = GroqBackend(settings)
        except Exception as e:
            raise HTTPException(status_code=503, detail=f"Groq GD backend initialization failed: {e}")
        return ModelRouter(settings, {"gd_generation": groq_backend})

@router.post(
    "/start",
    response_model=GDStartResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def start(
    request: GDStartRequest,
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    try:
        router_ = _backend_router(settings)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
        
    config = {
        "topic": request.topic,
        "num_rounds": request.num_rounds,
        "mode": request.mode,
        "similarity_threshold": 0.8,
        "user_name": get_user_display_name_from_token(raw_token)
    }
    
    manager = DiscussionManager(
        topic=request.topic,
        profiles=default_profiles(),
        config=config,
        router=router_
    )
    
    if settings.use_supabase_persistence:
        repo = SupabaseRepository()
        await repo.ensure_profile(user_id, raw_token)
        duration_by_rounds = {
            2: 5,
            4: 10,
            6: 15,
        }
        duration_min = duration_by_rounds.get(request.num_rounds, 10)
        session_data = {
            "user_id": user_id,
            "kind": "gd",
            "role": "Moderator",
            "domains": [request.mode],
            "topic": request.topic,
            "duration_min": duration_min,
            "question_count": request.num_rounds,
        }
        db_session = await repo.create_session(session_data, raw_token)
        session_id = db_session["id"]
    else:
        session_id = str(uuid.uuid4())
        gd_sessions.save(session_id, user_id, manager)
    
    return GDStartResponse(
        session_id=session_id,
        topic_analysis={
            "central_question": manager.analysis.central_question,
            "stakeholders": manager.analysis.stakeholders,
            "benefits": manager.analysis.benefits,
            "risks": manager.analysis.risks
        },
        participants=[
            {
                "name": p.profile.name,
                "role": p.profile.role,
                "initial_position": p.position
            }
            for p in manager.agents
        ]
    )

@router.post(

    "/respond",
    response_model=GDRespondResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def respond(
    request: GDRespondRequest, 
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    if settings.use_supabase_persistence:
        async with session_locks.lock(request.session_id):
            repo = SupabaseRepository()
            try:
                db_session = await repo.session(request.session_id, user_id, raw_token)
            except NotFoundError:
                raise HTTPException(status_code=404, detail="unknown or expired session_id")
            except RepositoryError as exc:
                raise HTTPException(status_code=503, detail=f"Database persistent session unreachable: {exc}")
            except Exception as exc:
                raise HTTPException(status_code=500, detail="Failed to load session details.")
                
            try:
                db_messages = await repo.messages(request.session_id, raw_token)
            except RepositoryError as exc:
                raise HTTPException(status_code=503, detail=f"Database persistent storage unreachable: {exc}")
            
            if db_session.get("status") == "completed":
                raise HTTPException(status_code=409, detail="Session is already finished.")
            
            try:
                router_ = _backend_router(settings)
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))
                
            if request.user_contribution and request.user_contribution.strip():
                user_text = request.user_contribution.strip()
                ai_turn_count = sum(1 for m in db_messages if m.get("speaker_type") == "agent")
                user_round = (ai_turn_count // 4) + 1
                user_envelope = {
                    "speaker": "You",
                    "round": user_round,
                    "action": "USER_CONTRIBUTION",
                    "target": None,
                    "position": 0.0,
                    "claim": user_text,
                    "response": user_text,
                    "confidence": 1.0,
                    "issue": "discussion",
                    "argument": {
                        "claim": user_text,
                        "reasoning": "User contribution",
                        "evidence_needed": "",
                        "assumptions": "",
                        "strength": 0.8,
                        "position": "NEUTRAL",
                        "issue": "discussion"
                    }
                }
                user_msg = {
                    "session_id": request.session_id,
                    "speaker": "You",
                    "speaker_type": "user",
                    "content": json.dumps(user_envelope),
                    "turn_index": len(db_messages)
                }
                try:
                    await repo.add_message(user_msg, raw_token)
                except RepositoryError as exc:
                    raise HTTPException(status_code=503, detail=f"Database persistent message write failed: {exc}")
                db_messages.append(user_msg)

            user_name = get_user_display_name_from_token(raw_token)
            config = {
                "topic": db_session["topic"],
                "num_rounds": db_session.get("question_count", 4),
                "mode": db_session["domains"][0] if db_session["domains"] else "balanced",
                "similarity_threshold": 0.8,
                "user_name": user_name
            }
            
            manager = DiscussionManager.from_history(
                history=db_messages,
                topic=db_session["topic"],
                config=config,
                router=router_
            )
            
            # Step generation offloaded to thread with 90s timeout
            try:
                turn = await asyncio.wait_for(
                    asyncio.to_thread(manager.step),
                    timeout=90.0
                )
            except asyncio.TimeoutError:
                raise HTTPException(status_code=504, detail="GD generation timed out.")
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Generation failed: {e}")
                
            if turn is None:
                return GDRespondResponse(
                    session_id=request.session_id,
                    turn=None,
                    finished=True
                )
                
            # Perform Groq Verification on the newly generated response text
            history_context = "\n".join(f"{t.speaker}: {t.response}" for t in manager.history[:-1][-5:])
            verified_text = await verify_gd_turn(
                topic=db_session["topic"],
                speaker_name=turn.speaker,
                stance=turn.position,
                unverified_text=turn.response,
                history_context=history_context,
                settings=settings
            )
            
            # If verifier changed/corrected the text, update ONLY the response field
            if verified_text != turn.response:
                turn.response = verified_text
            
            # Persist validated Turn using JSON envelope in content field
            arg_dict = {
                "claim": turn.argument.claim,
                "reasoning": turn.argument.reasoning,
                "evidence_needed": turn.argument.evidence_needed,
                "assumptions": turn.argument.assumptions,
                "strength": turn.argument.strength,
                "position": turn.argument.position,
                "issue": turn.argument.issue
            }
            
            envelope = {
                "speaker": turn.speaker,
                "round": turn.round,
                "action": turn.action,
                "target": turn.target,
                "position": turn.position,
                "claim": turn.claim,
                "response": turn.response,
                "confidence": turn.confidence,
                "issue": turn.argument.issue,
                "argument": arg_dict,
                "counter_target": turn.counter_target,
                "target_turn_index": turn.target_turn_index
            }
            
            serialized_content = json.dumps(envelope, separators=(",", ":"))
            if len(serialized_content) > 4000:
                # Compact optional internal argument metadata fields to fit <= 4000 limit without truncating response text
                arg_dict_compact = dict(arg_dict, reasoning="", assumptions="", evidence_needed="")
                envelope_compact = dict(envelope, argument=arg_dict_compact)
                serialized_content = json.dumps(envelope_compact, separators=(",", ":"))
                if len(serialized_content) > 4000:
                    arg_dict_compact["claim"] = ""
                    envelope_compact["argument"] = arg_dict_compact
                    serialized_content = json.dumps(envelope_compact, separators=(",", ":"))
            
            if len(serialized_content) > 4000:
                raise HTTPException(status_code=500, detail=f"Serialized content length ({len(serialized_content)}) exceeds database limit 4000.")

            message_data = {
                "session_id": request.session_id,
                "speaker": turn.speaker,
                "speaker_type": "agent",
                "content": serialized_content,
                "turn_index": len(db_messages)
            }
            
            try:
                await repo.add_message(message_data, raw_token)
            except RepositoryError as exc:
                raise HTTPException(status_code=503, detail=f"Database persistent agent message write failed: {exc}")
            
            return GDRespondResponse(
                session_id=request.session_id,
                turn=GDTurnResponse(
                    speaker=turn.speaker,
                    round=turn.round,
                    action=turn.action,
                    target=turn.target,
                    position=turn.position,
                    claim=turn.claim,
                    response=turn.response,
                    confidence=turn.confidence,
                    issue=turn.argument.issue,
                ),
                finished=False
            )
    else:
        async with session_locks.lock(request.session_id):
            manager: DiscussionManager | None = gd_sessions.load(request.session_id, user_id)
            if manager is None:
                raise HTTPException(status_code=404, detail="unknown or expired session_id")
            
            user_name = get_user_display_name_from_token(raw_token)
            if user_name:
                manager.config["user_name"] = user_name
                
            if request.user_contribution and request.user_contribution.strip():
                user_text = request.user_contribution.strip()
                user_arg = Argument(
                    claim=user_text,
                    reasoning="User contribution",
                    evidence_needed="",
                    assumptions="",
                    strength=0.8,
                    position="NEUTRAL",
                    issue="discussion",
                    speaker="You",
                    round=manager.round_no
                )
                user_turn = Turn(
                    speaker="You",
                    round=manager.round_no,
                    action="USER_CONTRIBUTION",
                    target=None,
                    position=0.0,
                    claim=user_text,
                    response=user_text,
                    confidence=1.0,
                    argument=user_arg
                )
                manager.history.append(user_turn)

            try:
                turn = manager.step()
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Generation failed: {e}")
                
            if turn is None:
                return GDRespondResponse(
                    session_id=request.session_id,
                    turn=None,
                    finished=True
                )
                
            # Perform Groq Verification on the newly generated response text
            history_context = "\n".join(f"{t.speaker}: {t.response}" for t in manager.history[:-1][-5:])
            try:
                verified_text = await verify_gd_turn(
                    topic=getattr(manager, "topic", "Group Discussion"),
                    speaker_name=turn.speaker,
                    stance=turn.position,
                    unverified_text=turn.response,
                    history_context=history_context,
                    settings=settings
                )
            except Exception:
                manager.pop_last_turn()
                raise
            
            if verified_text != turn.response:
                turn.response = verified_text
                
            return GDRespondResponse(
                session_id=request.session_id,
                turn=GDTurnResponse(
                    speaker=turn.speaker,
                    round=turn.round,
                    action=turn.action,
                    target=turn.target,
                    position=turn.position,
                    claim=turn.claim,
                    response=turn.response,
                    confidence=turn.confidence,
                    issue=turn.argument.issue,
                ),
                finished=False
            )

@router.post(
    "/finish/{session_id}",
    response_model=GDFinishResponse,
    responses={401: {"description": "Missing or invalid authentication token."}},
)
async def finish(
    session_id: str, 
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
    settings: Settings = Depends(get_settings),
):
    if settings.use_supabase_persistence:
        async with session_locks.lock(session_id):
            repo = SupabaseRepository()
            try:
                db_session = await repo.session(session_id, user_id, raw_token)
            except NotFoundError:
                raise HTTPException(status_code=404, detail="unknown or expired session_id")
            except RepositoryError as exc:
                raise HTTPException(status_code=503, detail=f"Database persistent session unreachable: {exc}")
            except Exception as exc:
                raise HTTPException(status_code=500, detail="Failed to load session details.")
                
            db_messages = await repo.messages(session_id, raw_token)
            
            try:
                router_ = _backend_router(settings)
            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))
                
            config = {
                "topic": db_session["topic"],
                "num_rounds": db_session.get("question_count", 4),
                "mode": db_session["domains"][0] if db_session["domains"] else "balanced",
                "similarity_threshold": 0.8
            }
            
            manager = DiscussionManager.from_history(
                history=db_messages,
                topic=db_session["topic"],
                config=config,
                router=router_
            )
            
            evaluator = DiscussionEvaluator()
            metrics = evaluator.evaluate(manager)
            summary = evaluator.summary(manager)
            
            # Map parameters strictly to schema fields
            feedback_data = {
                "session_id": session_id,
                "overall_score": int(round(metrics.get("quality_score", 0.0))),
                "scores": metrics,
                "strengths": summary.get("strongest_arguments", []),
                "weaknesses": summary.get("points_of_disagreement", []),
                "missing_concepts": summary.get("unresolved_questions", []),
                "recommendations": summary.get("points_of_agreement", []),
                "summary": f"Consensus: {summary.get('final_consensus', 'N/A')}. Topic: {summary.get('topic_summary', 'N/A')}."
            }
            
            await repo.upsert_feedback(feedback_data, raw_token)
            await repo.update_session(session_id, user_id, raw_token, {"status": "completed"})
            
            return GDFinishResponse(
                session_id=session_id,
                metrics=metrics,
                summary=summary
            )
    else:
        async with session_locks.lock(session_id):
            manager: DiscussionManager | None = gd_sessions.load(session_id, user_id)
            if manager is None:
                raise HTTPException(status_code=404, detail="unknown or expired session_id")
                
            evaluator = DiscussionEvaluator()
            metrics = evaluator.evaluate(manager)
            summary = evaluator.summary(manager)
            
            gd_sessions.delete(session_id, user_id)
            
            session_summary = {
                "id": session_id,
                "kind": "gd",
                "topic": getattr(manager, "topic", getattr(manager, "topic_name", "Group Discussion")),
                "date": "Today",
                "duration": f"{len(manager.history) * 2} min" if (manager and manager.history) else "10 min",
                "score": int(round(metrics.get("quality_score", metrics.get("overall_score", 75.0)))),
                "report": {
                    "metrics": metrics,
                    "summary": summary,
                    "strengths": summary.get("strongest_arguments", []),
                    "weaknesses": summary.get("points_of_disagreement", []),
                    "missing_concepts": summary.get("unresolved_questions", []),
                    "recommendations": summary.get("points_of_agreement", [])
                },
                "transcript": [
                    {"speaker": t.speaker, "text": t.response} for t in (manager.history if manager and manager.history else [])
                ]
            }
            from app.utils.session_store import completed_sessions
            completed_sessions.add_completed_session(user_id, session_summary)

            return GDFinishResponse(
                session_id=session_id,
                metrics=metrics,
                summary=summary
            )



