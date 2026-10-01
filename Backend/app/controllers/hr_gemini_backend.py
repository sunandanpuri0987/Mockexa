from __future__ import annotations

import json
import logging

from app.controllers.hr_controller import HREvaluation, HRQuestion, _STYLE_PROFILES, normalize_hr_style
from app.providers.llm_backend import LLMBackendError
from app.providers.model_router import ModelRouter

logger = logging.getLogger("mockexa.hr_gemini_backend")


_SYSTEM_PROMPT = (
    "You are an empathetic, perceptive, and experienced Senior HR Interviewer conducting a realistic behavioral interview. "
    "You speak naturally like a real person—warm, professional, and conversational, NOT like an automated robot. "
    "Evaluate the candidate's answer with high emotional intelligence and workplace judgment.\n\n"
    "CRITICAL CONVERSATIONAL RULES:\n"
    "1. REALISTIC COUNTER-QUESTIONS FOR WRONG, FLAWED, OR EVASIVE ANSWERS:\n"
    "   - In a real interview, when a candidate gives an incorrect answer, makes a flawed decision, evades accountability, "
    "     blames teammates, suggests an unworkable approach, or gives a superficial response, a real interviewer DOES NOT ignore it. "
    "   - You MUST set 'needs_follow_up': true and ask a direct, realistic counter-question in 'follow_up_question'. "
    "   - Challenge the candidate naturally on their specific words or mistake. For example:\n"
    "     * 'Wait, if you decided to bypass your team lead and push code directly, didn't that risk breaking production? How did you justify taking that risk?'\n"
    "     * 'You mentioned that the delivery failed because the QA team was slow. But as the engineer owning the feature, what steps did you take before the deadline to unblock them?'\n"
    "     * 'Help me understand: wouldn't reacting that way in front of the client damage trust? How did you resolve that afterward?'\n"
    "     * 'Why did you choose that particular approach over consulting your manager or team first?'\n"
    "2. CONVERSATIONAL BRIDGE FOR NEXT TOPIC:\n"
    "   - In 'conversational_bridge', provide a 1-sentence natural human acknowledgment or transition that bridges from the candidate's response to the next topic (e.g., 'Thanks for sharing that background on scaling your APIs—that gives good context.', or 'I appreciate your transparency on that conflict.').\n"
    "3. ROLE-TAILORED NEXT TOPIC QUESTION:\n"
    "   - In 'next_topic_question', formulate a realistic next interview question testing an essential behavioral dimension (e.g. Failure/Resilience, Team Conflict, Handling Ambiguity/Tough Deadlines, Receiving Critical Feedback, or Leadership). "
    "   - Tailor the question specifically to the candidate's target role, experience level, and the concrete points they just discussed. Make it sound like a curious, experienced interviewer having a genuine conversation, not reading a script.\n"
    "4. TONE AND SAFETY:\n"
    "   - Sound composed, curious, and professional. Never be hostile, humiliating, or derogatory.\n"
    "   - Ask exactly one clear, targeted question, never compound questions.\n\n"
    "Output ONLY a JSON object with exactly these fields and no others:\n"
    '{"clarity": float 0-1, "specificity": float 0-1, "ownership": float 0-1, '
    '"communication": float 0-1, "teamwork": float 0-1, "leadership": float 0-1, '
    '"problem_solving": float 0-1, "feedback": string, "needs_follow_up": boolean, '
    '"follow_up_question": string, "follow_up_category": string, '
    '"probe_focus": one of ["specificity", "ownership", "consistency", "conflict", "failure", '
    '"judgment", "resilience", "self_awareness", "none"], "pressure_level": integer 1-3, '
    '"observed_signal": string, "conversational_bridge": string, "next_topic_question": string}\n'
    "The feedback string should be a concise 1-2 sentence constructive critique of the answer. "
    "If needs_follow_up is false, follow_up_question must be an empty string, probe_focus must be 'none', "
    "and pressure_level must be 1. Pressure level 3 is reserved for a material contradiction, blame shifting, "
    "or a serious judgment gap; it must still sound calm and respectful. "
    "Do not include any explanation, markdown, or text outside the JSON object. "
    "Do not reveal your reasoning process, only the final JSON."
)


class GeminiHRBackend:
    def __init__(self, model_router: ModelRouter, fallback=None):
        self._router = model_router
        self._fallback = fallback

    def evaluate(self, question: HRQuestion, answer: str) -> HREvaluation:
        return self.evaluate_with_context(question, answer, ())

    def evaluate_with_context(self, question: HRQuestion, answer: str, history, role: str = "", experience: str = "", resume_context: str = "", job_description: str = "", **kwargs) -> HREvaluation:
        style = normalize_hr_style(question.interview_style)
        # Relevance is a deterministic gate: an LLM must never award a fluent
        # score to an answer that did not address the question.
        if self._fallback is not None:
            grounded = self._fallback.evaluate_with_context(question, answer, history)
            if grounded.follow_up_category == "Relevance clarification":
                return grounded
        prior_context = "\n".join(
            f"- Earlier question: {prior_q.question}\n  Candidate answer: {prior_answer}"
            for prior_q, prior_answer, _ in history
        ) or "None"
        resume_block = f"CANDIDATE RESUME / PROJECTS CONTEXT:\n{resume_context}\n\n" if resume_context else ""
        jd_block = f"TARGET JOB DESCRIPTION (JD) REQUIREMENTS:\n{job_description}\n\n" if job_description else ""
        user_prompt = (
            f"TARGET ROLE: {role or 'Candidate'}\n"
            f"EXPERIENCE LEVEL: {experience or 'General'}\n"
            f"{resume_block}{jd_block}"
            f"QUESTION CATEGORY: {question.category}\n"
            f"INTERVIEW STYLE: {style}\nSTYLE FOCUS: {_STYLE_PROFILES[style]}\n"
            f"INTERVIEW QUESTION ASKED: {question.question}\n"
            f"CANDIDATE'S RESPONSE: {answer}\n"
            f"RECENT INTERVIEW CONTEXT:\n{prior_context}\n\n"
            "Assess only evidence actually present in the candidate response; never reward fluent but irrelevant text. "
            "If it is unrelated, nonsense, evasive, or does not answer the question, score it below 0.20, explicitly say so in feedback, "
            "and ask a clarification of the same question instead of advancing. Assess like a real senior HR interviewer. "
            "If the answer is flawed, wrong, evasive, blame-shifting, or lacks critical evidence/ownership, "
            "set needs_follow_up to true and formulate a realistic, natural counter-question directly probing that specific point. "
            "When resume context is provided, ground your questions and probing in their actual projects, technologies, and work. "
            "If a job description is provided, test requirements from that JD. "
            "Also include a natural 1-sentence conversational_bridge connecting their response to the conversation, "
            "and in next_topic_question provide a thoughtful, role-tailored behavioral question for the next competency."
        )
        try:
            result = self._router.generate(
                task="hr_eval",
                system_prompt=_SYSTEM_PROMPT,
                user_prompt=user_prompt,
            )
            parsed = json.loads(result.text)
            
            clarity = float(parsed["clarity"])
            specificity = float(parsed["specificity"])
            ownership = float(parsed["ownership"])
            communication = float(parsed["communication"])
            teamwork = float(parsed["teamwork"])
            leadership = float(parsed["leadership"])
            problem_solving = float(parsed["problem_solving"])
            scores = [clarity, specificity, ownership, communication, teamwork, leadership, problem_solving]
            if any(score < 0.0 or score > 1.0 for score in scores):
                raise ValueError("HR evaluation score outside [0, 1]")

            needs_follow_up = bool(parsed.get("needs_follow_up", False))
            follow_up_question = str(parsed.get("follow_up_question", "")).strip()
            probe_focus = str(parsed.get("probe_focus", "none")).strip().lower()
            pressure_level = max(1, min(3, int(parsed.get("pressure_level", 1))))
            observed_signal = str(parsed.get("observed_signal", "")).strip()
            conversational_bridge = str(parsed.get("conversational_bridge", "")).strip()
            next_topic_question = str(parsed.get("next_topic_question", "")).strip()
            if not needs_follow_up:
                follow_up_question = ""
                probe_focus = "none"
                pressure_level = 1
            
            overall = round(
                (clarity + specificity + ownership + communication + teamwork + leadership + problem_solving) / 7.0,
                3,
            )
            return HREvaluation(
                clarity=clarity,
                specificity=specificity,
                ownership=ownership,
                communication=communication,
                teamwork=teamwork,
                leadership=leadership,
                problem_solving=problem_solving,
                feedback=str(parsed.get("feedback", "No feedback provided.")),
                overall_score=overall,
                needs_follow_up=needs_follow_up,
                follow_up_question=follow_up_question,
                follow_up_category=str(parsed.get("follow_up_category", "")).strip(),
                probe_focus=probe_focus,
                pressure_level=pressure_level,
                observed_signal=observed_signal,
                conversational_bridge=conversational_bridge,
                next_topic_question=next_topic_question,
            )
        except (LLMBackendError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
            logger.warning("gemini_hr_eval_failed reason=%s", exc)
            if self._fallback is not None:
                fallback_with_context = getattr(self._fallback, "evaluate_with_context", None)
                if callable(fallback_with_context):
                    return fallback_with_context(question, answer, history)
                return self._fallback.evaluate(question, answer)
            return HREvaluation(
                clarity=0.0,
                specificity=0.0, ownership=0.0, communication=0.0,
                teamwork=0.0, leadership=0.0, problem_solving=0.0,
                feedback="Evaluation failed.", overall_score=0.0,
            )
