from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Protocol

logger = logging.getLogger("mockexa.hr_controller")


@dataclass(frozen=True)
class HRQuestion:
    id: str
    question: str
    category: str
    interview_style: str = "General HR"


_STYLE_PROFILES = {
    "General HR": "balanced role fit, communication, motivation, and professional judgment",
    "Behavioral": "past evidence using situation, action, result, and reflection",
    "Leadership": "ownership, influence, decisions, delegation, and measurable team impact",
    "Situational": "reasoning through a realistic hypothetical, trade-offs, stakeholders, and risk",
    "Stress Interview": "calm, concise judgment under respectful challenge and ambiguity",
}


def normalize_hr_style(value: str) -> str:
    cleaned = " ".join(str(value or "").split()).lower()
    return next((name for name in _STYLE_PROFILES if name.lower() == cleaned), "General HR")


@dataclass(frozen=True)
class HREvaluation:
    clarity: float
    specificity: float
    ownership: float
    communication: float
    teamwork: float
    leadership: float
    problem_solving: float
    feedback: str
    overall_score: float
    needs_follow_up: bool = False
    follow_up_question: str = ""
    follow_up_category: str = ""
    probe_focus: str = ""
    pressure_level: int = 1
    observed_signal: str = ""
    conversational_bridge: str = ""
    next_topic_question: str = ""


class HRBackend(Protocol):
    def evaluate(self, question: HRQuestion, answer: str) -> HREvaluation: ...


class CuratedHRBackend:
    """Fast evidence-based evaluator and safe fallback for HR practice."""

    def evaluate(self, question: HRQuestion, answer: str) -> HREvaluation:
        return self.evaluate_with_context(question, answer, ())

    def evaluate_with_context(self, question: HRQuestion, answer: str, history) -> HREvaluation:
        clean = " ".join(answer.strip().split())
        words = re.findall(r"[a-zA-Z][a-zA-Z'-]*", clean.lower())
        tokens = set(words)
        filler = {"anything", "whatever", "random", "nothing", "skip", "next", "dont", "don't", "know", "idk", "okay", "ok", "yes", "no"}
        question_tokens = set(re.findall(r"[a-zA-Z][a-zA-Z'-]*", question.question.lower()))
        stop = {"the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "with", "what", "how", "tell", "me", "about", "your", "you", "did", "was", "were", "is", "that", "this"}
        workplace = {"team", "project", "work", "manager", "client", "customer", "deadline", "role", "career", "experience", "job", "company", "stakeholder", "problem", "decision", "feedback", "conflict", "result", "goal", "task", "skill", "learned", "responsibility", "student", "studying", "college", "university", "degree", "engineer", "developer", "btech", "graduate", "intern", "internship"}
        meaningful = tokens - stop - filler
        topical_overlap = meaningful & ((question_tokens - stop) | workplace)
        explicit_evasion = bool(tokens & filler) and len(meaningful) < 4
        irrelevant = len(words) >= 3 and not topical_overlap and len(meaningful) < 8
        if len(words) < 3:
            return HREvaluation(
                clarity=0.1, specificity=0.0, ownership=0.0, communication=0.1,
                teamwork=0.0, leadership=0.0, problem_solving=0.0,
                feedback="The answer is too brief to evaluate. Add a concrete situation, your action, and the result.",
                overall_score=0.04, needs_follow_up=True,
                follow_up_question="That was quite brief. Could you walk me through a specific situation and what you personally did?",
                follow_up_category="Specificity probe", probe_focus="specificity", pressure_level=1,
                observed_signal="The response did not provide enough behavioral evidence.",
                conversational_bridge="Understood. Let's move to our next topic:",
            )
        if explicit_evasion or irrelevant:
            key_phrase = " ".join(words[:8])
            return HREvaluation(
                clarity=0.18, specificity=0.0, ownership=0.0, communication=0.12,
                teamwork=0.0, leadership=0.0, problem_solving=0.0,
                feedback=(f'The response (“{key_phrase}”) did not answer the question, so it cannot be scored as interview evidence. '
                          "Acknowledge the question and give one relevant example or a clear, reasoned answer."),
                overall_score=0.043, needs_follow_up=True,
                follow_up_question=f"That did not address my question. {question.question}",
                follow_up_category="Relevance clarification", probe_focus="relevance", pressure_level=2,
                observed_signal="The candidate response was evasive or unrelated to the question.",
                conversational_bridge="Let's stay with the question before moving on.",
            )

        sentence_count = max(1, len(re.findall(r"[.!?]+", clean)))
        clarity = min(1.0, 0.35 + min(len(words), 80) / 130 + min(sentence_count, 4) * 0.06)
        has_number = bool(re.search(r"\b\d+(?:\.\d+)?(?:%|x)?\b", clean))
        example_markers = {"when", "during", "project", "deadline", "customer", "manager", "team", "situation"}
        action_markers = {"decided", "created", "implemented", "changed", "spoke", "asked", "prioritized", "resolved", "led", "proposed", "coordinated", "analyzed", "designed", "negotiated", "aligned"}
        result_markers = {"result", "improved", "reduced", "increased", "delivered", "learned", "outcome", "saved"}
        ownership_markers = {"i", "my", "personally", "owned", "responsibility", "accountable"}
        teamwork_markers = {"team", "teammate", "stakeholder", "collaborated", "feedback", "listened", "manager", "aligned", "coordinated"}
        leadership_markers = {"led", "aligned", "influenced", "delegated", "mentored", "decision", "initiative", "coordinated", "negotiated"}
        problem_markers = {"problem", "risk", "option", "options", "alternative", "alternatives", "tradeoff", "tradeoffs", "because", "therefore", "root", "solution", "measured", "analyzed", "bottleneck", "constraint", "data", "metric"}

        specificity = min(1.0, 0.16 * len(tokens & example_markers) + 0.16 * len(tokens & action_markers) + 0.18 * bool(tokens & result_markers) + 0.16 * has_number)
        ownership = min(1.0, 0.24 * len(tokens & ownership_markers) + 0.18 * len(tokens & action_markers))
        communication = min(1.0, 0.30 + min(len(words), 100) / 170 + 0.12 * bool(tokens & {"first", "then", "finally", "however"}))
        teamwork = min(1.0, 0.18 + 0.16 * len(tokens & teamwork_markers))
        leadership = min(1.0, 0.12 + 0.18 * len(tokens & leadership_markers) + 0.12 * bool(tokens & ownership_markers))
        problem_solving = min(1.0, 0.14 + 0.15 * len(tokens & problem_markers) + 0.10 * bool(tokens & action_markers))
        scores = [clarity, specificity, ownership, communication, teamwork, leadership, problem_solving]
        style = normalize_hr_style(question.interview_style)
        weights = {
            "General HR": (1, 1, 1, 1.3, 0.8, 0.7, 0.8),
            "Behavioral": (0.8, 1.5, 1.3, 1, 0.8, 0.7, 0.9),
            "Leadership": (0.7, 1, 1.4, 0.8, 1, 1.6, 1.2),
            "Situational": (0.8, 0.7, 0.8, 1, 1, 1, 1.7),
            "Stress Interview": (1.3, 0.8, 1.2, 1.4, 0.7, 0.9, 1.4),
        }[style]
        overall = round(sum(score * weight for score, weight in zip(scores, weights)) / sum(weights), 3)

        blame_markers = {"fault", "blame", "they", "he", "she", "stupid", "useless", "idiot", "wrong", "hate", "fired", "yelled", "ignored"}
        has_blame = bool(tokens & blame_markers) and ownership < 0.50

        weakest_name, weakest = min(
            (("specificity", specificity), ("ownership", ownership), ("communication", communication),
             ("teamwork", teamwork), ("leadership", leadership), ("problem_solving", problem_solving)),
            key=lambda item: item[1],
        )
        needs_follow_up = (weakest < 0.52 or has_blame or overall < 0.60) and len(history) < 3

        if style == "Stress Interview" and overall < 0.72:
            followup_q = "I need a precise answer under pressure: what would you do first, and which risk would you personally own?"
            category, focus, pressure = "Composure probe", "judgment", 3
            signal = "The answer did not yet demonstrate concise judgment under pressure."
        elif style == "Situational" and problem_solving < 0.68:
            followup_q = "What would be your first concrete action, and which trade-off would you accept?"
            category, focus, pressure = "Scenario judgment probe", "judgment", 2
            signal = "The hypothetical response lacked a concrete decision and trade-off."
        elif style == "Leadership" and leadership < 0.68:
            followup_q = "What decision did you personally make, and how did you bring resistant people with you?"
            category, focus, pressure = "Leadership impact probe", "ownership", 2
            signal = "Leadership influence and personal decision-making were not demonstrated."
        elif has_blame:
            followup_q = "Wait, help me understand—even if there were issues with others, which decision was personally yours, and what consequence did you accept?"
            category = "Accountability probe"
            focus = "ownership"
            pressure = 2
            signal = "Observed blame-shifting and limited personal accountability."
        elif weakest_name == "ownership":
            followup_q = "Wait, which decision was personally yours in that situation, and what consequence did you accept?"
            category = "Accountability probe"
            focus = "ownership"
            pressure = 2
            signal = "Ownership was shifted or unclear."
        elif weakest_name == "problem_solving":
            followup_q = "Before taking that route, what alternative options did you consider, and why did you believe that was the right approach?"
            category = "Judgment probe"
            focus = "problem_solving"
            pressure = 2
            signal = "Alternative options and trade-offs were not articulated."
        elif weakest_name == "teamwork":
            followup_q = "That sounds like a challenging situation. How did you incorporate the other person's perspective without avoiding the disagreement?"
            category = "Collaboration probe"
            focus = "teamwork"
            pressure = 2
            signal = "Constructive collaboration was not demonstrated."
        elif weakest_name == "communication":
            followup_q = "What exactly did you say to the other person at that moment, and how did they respond?"
            category = "Communication probe"
            focus = "communication"
            pressure = 1
            signal = "Direct communication details were missing."
        else:
            followup_q = "Could you walk me through a specific real-world example of that, and what measurable result followed your action?"
            category = "Specificity probe"
            focus = "specificity"
            pressure = 1
            signal = "Vague or generalized response without concrete evidence."

        if overall >= 0.72:
            bridge = "Thanks for walking me through that, that makes good sense."
        elif overall >= 0.48:
            bridge = "Understood, thanks for providing that context."
        else:
            bridge = "Fair enough, let's keep moving forward."

        strongest_name, strongest = max(
            (("specificity", specificity), ("ownership", ownership), ("communication", communication),
             ("teamwork", teamwork), ("leadership", leadership), ("problem_solving", problem_solving)),
            key=lambda item: item[1],
        )
        if overall >= 0.75:
            feedback = (
                f"Strong {strongest_name.replace('_', ' ')}: the answer gives credible personal action and outcome evidence. "
                f"To make it interview-ready, sharpen {weakest_name.replace('_', ' ')} with one precise detail."
            )
        elif overall >= 0.48:
            feedback = (
                f"The answer shows some {strongest_name.replace('_', ' ')}, but {weakest_name.replace('_', ' ')} remains unclear. "
                "Add the exact decision you made, why you made it, and the measurable result."
            )
        else:
            feedback = (
                f"The response is too general to establish {weakest_name.replace('_', ' ')}. "
                "Use one relevant situation and clearly separate your action from the team's action and result."
            )
        return HREvaluation(
            clarity=round(clarity, 3), specificity=round(specificity, 3), ownership=round(ownership, 3),
            communication=round(communication, 3), teamwork=round(teamwork, 3), leadership=round(leadership, 3),
            problem_solving=round(problem_solving, 3), feedback=feedback, overall_score=overall,
            needs_follow_up=needs_follow_up,
            follow_up_question=followup_q if needs_follow_up else "",
            follow_up_category=category if needs_follow_up else "",
            probe_focus=focus if needs_follow_up else "none", pressure_level=pressure if needs_follow_up else 1,
            observed_signal=signal if needs_follow_up else "",
            conversational_bridge=bridge,
        )


# Curated question bank based on the STAR method
_HR_QUESTION_BANK = [
    HRQuestion(
        id="hr-intro",
        question="Please introduce yourself and briefly describe your professional background and current role.",
        category="Introduction",
    ),
    HRQuestion(
        id="hr-failure",
        question="Tell me about a meaningful failure. What part was genuinely your responsibility, and what did you change afterward?",
        category="Accountability and resilience",
    ),
    HRQuestion(
        id="hr-conflict",
        question="Tell me about a serious disagreement with a teammate or manager. What did you say, and what was the eventual outcome?",
        category="Conflict handling",
    ),
    HRQuestion(
        id="hr-feedback",
        question="Describe difficult feedback you initially disagreed with. How did you respond in the moment, and what did you do later?",
        category="Self-awareness and coachability",
    ),
    HRQuestion(
        id="hr-pressure",
        question="Imagine two senior stakeholders demand conflicting outcomes under the same deadline. How would you decide, communicate, and accept the consequences?",
        category="Judgment under pressure",
    ),
    HRQuestion(
        id="hr-leadership",
        question="Describe a situation where you led without formal authority. How did you handle resistance and measure whether people actually aligned?",
        category="Leadership",
    ),
    HRQuestion(
        id="hr-teamwork",
        question="Tell me about working closely with someone whose style frustrated you. How did you adapt without lowering the quality bar?",
        category="Teamwork and emotional regulation",
    ),
    HRQuestion(
        id="hr-ethics",
        question="Tell me about a time when the easiest business decision conflicted with what you believed was right. What did you do?",
        category="Integrity and judgment",
    ),
    HRQuestion(
        id="hr-ambiguity",
        question="Describe a high-stakes decision you made with incomplete information. Which assumption worried you most, and how did you manage that risk?",
        category="Decision-making under ambiguity",
    ),
    HRQuestion(
        id="hr-motivation",
        question="What kind of work environment brings out your worst habits, and what evidence shows you can manage them professionally?",
        category="Self-awareness and motivation",
    ),
]


_UNSAFE_FOLLOW_UP_TERMS = {
    "humiliate", "embarrass", "break you", "trap you", "confuse you",
    "mental illness", "diagnose", "religion", "caste", "pregnant",
    "marital status", "sexual orientation",
}


def _safe_follow_up_text(raw: str) -> str:
    """Validate generated probes as professional interview questions."""
    text = " ".join(str(raw or "").strip().split())
    if not text:
        return ""
    lowered = text.lower()
    if any(term in lowered for term in _UNSAFE_FOLLOW_UP_TERMS):
        return ""
    words = text.split()
    if len(words) < 4 or len(words) > 70:
        return ""
    if not text.endswith("?"):
        text += "?"
    return text


class HRController:
    """
    Deterministic, authoritative state machine for HR interviews.
    """
    def __init__(self, backend: HRBackend):
        self._backend = backend
        self.max_questions = len(_HR_QUESTION_BANK)
        self.current_index = 0
        self.history: list[tuple[HRQuestion, str, HREvaluation]] = []
        self._current_question: HRQuestion | None = None
        self._next_base_index = 0
        self._followups_used = 0
        self._started = False
        self._finished = False
        self.interview_style = "General HR"
        self.candidate_name = ""
        self.target_role = ""
        self.experience = ""
        self.resume_context = ""
        self.job_description = ""

    @classmethod
    def from_history(
        cls,
        max_questions: int,
        history: list[dict],
        backend: HRBackend | None = None,
        interview_style: str = "General HR",
        candidate_name: str = "",
        target_role: str = "",
        experience: str = "",
        resume_context: str = "",
        job_description: str = "",
    ) -> HRController:
        controller = cls(backend)
        controller.start(
            max_questions,
            interview_style=interview_style,
            candidate_name=candidate_name,
            target_role=target_role,
            experience=experience,
            resume_context=resume_context,
            job_description=job_description,
        )
        for answer_row in history:
            evaluation_data = answer_row.get("evaluation") or {}
            question_id = evaluation_data.get("question_id") or answer_row.get("question_id")
            question = next((q for q in _HR_QUESTION_BANK if q.id == question_id), None)
            if not question:
                question_text = str(evaluation_data.get("question_text") or "").strip()
                if not question_text:
                    continue
                question = HRQuestion(
                    id=str(question_id or f"hr-restored-{controller.current_index}"),
                    question=question_text,
                    category=str(evaluation_data.get("question_category") or "Adaptive follow-up"),
                    interview_style=controller.interview_style,
                )

            evaluation_data = answer_row.get("evaluation") or {}
            evaluation = HREvaluation(
                clarity=float(evaluation_data.get("clarity", 0.0)),
                specificity=float(evaluation_data.get("specificity", 0.0)),
                ownership=float(evaluation_data.get("ownership", 0.0)),
                communication=float(evaluation_data.get("communication", 0.0)),
                teamwork=float(evaluation_data.get("teamwork", 0.0)),
                leadership=float(evaluation_data.get("leadership", 0.0)),
                problem_solving=float(evaluation_data.get("problem_solving", 0.0)),
                feedback=evaluation_data.get("feedback", ""),
                overall_score=float(evaluation_data.get("overall_score", 0.0)),
                needs_follow_up=bool(evaluation_data.get("needs_follow_up", False)),
                follow_up_question=str(evaluation_data.get("follow_up_question", "")),
                follow_up_category=str(evaluation_data.get("follow_up_category", "")),
                probe_focus=str(evaluation_data.get("probe_focus", "")),
                pressure_level=int(evaluation_data.get("pressure_level", 1)),
                observed_signal=str(evaluation_data.get("observed_signal", "")),
                conversational_bridge=str(evaluation_data.get("conversational_bridge", "")),
            )
            answer_content = answer_row.get("content", "")
            controller._record_answer(question, answer_content, evaluation)
        return controller

    def start(
        self,
        max_questions: int = 5,
        interview_style: str = "General HR",
        candidate_name: str = "",
        target_role: str = "",
        experience: str = "",
        resume_context: str = "",
        job_description: str = "",
    ) -> HRQuestion:
        if self._started:
            raise ValueError("HR session already started.")
        self.max_questions = min(max_questions, len(_HR_QUESTION_BANK))
        self._started = True
        self.interview_style = normalize_hr_style(interview_style)
        self.candidate_name = candidate_name.strip()
        self.target_role = target_role.strip()
        self.experience = experience.strip()
        self.resume_context = resume_context.strip()
        self.job_description = job_description.strip()

        base = self._question_order()[0]
        if self.target_role and base.id == "hr-intro":
            name_greeting = f"Hi {self.candidate_name}, " if self.candidate_name else "Hello! "
            role_spec = f" for the {self.target_role} position" if self.target_role else ""
            if self.resume_context:
                custom_intro = (
                    f"{name_greeting}welcome to your interview{role_spec}. "
                    f"I reviewed your resume and background. "
                    f"To kick things off, could you introduce yourself, highlight the project or accomplishment "
                    f"you are most proud of, and share what motivated you to apply for this role?"
                )
            else:
                custom_intro = (
                    f"{name_greeting}welcome to your interview{role_spec}. "
                    f"To kick things off, could you briefly introduce yourself, highlight your professional journey, "
                    f"and share what motivated you to pursue this role?"
                )
            self._current_question = HRQuestion("hr-intro", custom_intro, base.category, self.interview_style)
        else:
            self._current_question = HRQuestion(base.id, self._styled_question(base), base.category, self.interview_style)
        self._next_base_index = 1
        return self._current_question

    def _question_order(self) -> list[HRQuestion]:
        preferred = {
            "General HR": [q.id for q in _HR_QUESTION_BANK],
            "Behavioral": ["hr-failure", "hr-conflict", "hr-feedback", "hr-teamwork", "hr-ambiguity"],
            "Leadership": ["hr-leadership", "hr-conflict", "hr-pressure", "hr-teamwork", "hr-failure"],
            "Situational": ["hr-pressure", "hr-ambiguity", "hr-ethics", "hr-conflict", "hr-leadership"],
            "Stress Interview": ["hr-pressure", "hr-failure", "hr-conflict", "hr-ambiguity", "hr-feedback"],
        }[self.interview_style]
        by_id = {q.id: q for q in _HR_QUESTION_BANK}
        selected = [by_id[qid] for qid in preferred]
        return selected + [q for q in _HR_QUESTION_BANK if q.id not in preferred]

    def _styled_question(self, question: HRQuestion) -> str:
        prefixes = {
            "General HR": "",
            "Behavioral": "Please use a specific past example. ",
            "Leadership": "Focus on your personal leadership impact. ",
            "Situational": "Think through this scenario step by step. ",
            "Stress Interview": "Be concise and defend your judgment. ",
        }
        return prefixes[self.interview_style] + question.question

    def get_next_question(self) -> HRQuestion | None:
        if not self._started:
            return None
        if self.current_index >= self.max_questions or self._finished:
            return None
        return self._current_question

    def submit_answer(self, answer: str) -> tuple[HREvaluation, HRQuestion | None]:
        if not self._started:
            raise RuntimeError("Cannot submit answer before starting.")
        if self._finished or self.current_index >= self.max_questions:
            raise RuntimeError("Interview is already complete.")

        question = self._current_question
        if question is None:
            raise RuntimeError("No active HR question is available.")
        evaluate_with_context = getattr(self._backend, "evaluate_with_context", None)
        if callable(evaluate_with_context):
            try:
                evaluation = evaluate_with_context(
                    question, answer, tuple(self.history[-3:]),
                    role=self.target_role,
                    experience=self.experience,
                    resume_context=self.resume_context,
                    job_description=self.job_description,
                )
            except TypeError:
                evaluation = evaluate_with_context(question, answer, tuple(self.history[-3:]))
        else:
            evaluation = self._backend.evaluate(question, answer)
        self._record_answer(question, answer, evaluation)
        next_q = self.get_next_question()
        return evaluation, next_q

    def _default_bridge_for(self, evaluation: HREvaluation, answer: str) -> str:
        """Provide a natural human conversational transition if the backend did not generate one."""
        clean = answer.strip()
        if evaluation.overall_score >= 0.72:
            return "Thanks for walking me through that, that makes good sense."
        elif evaluation.overall_score >= 0.45:
            return "Understood, thanks for providing that context."
        elif len(clean.split()) < 6:
            return "Thanks for that brief overview."
        return "I appreciate you sharing that perspective."

    def _record_answer(self, question: HRQuestion, answer: str, evaluation: HREvaluation) -> None:
        self.history.append((question, answer, evaluation))
        self.current_index += 1

        if self.current_index >= self.max_questions:
            self._finished = True
            self._current_question = None
            return

        follow_up = self._adaptive_follow_up(question, evaluation)
        if follow_up is not None:
            self._current_question = follow_up
            self._followups_used += 1
            return

        ordered = self._question_order()
        if self._next_base_index < len(ordered):
            base_q = ordered[self._next_base_index]
            self._next_base_index += 1

            bridge = evaluation.conversational_bridge.strip()
            if not bridge:
                bridge = self._default_bridge_for(evaluation, answer)

            dynamic_q = evaluation.next_topic_question.strip()
            if dynamic_q and len(dynamic_q) > 15:
                bridged_text = f"{bridge} {dynamic_q}" if bridge and not dynamic_q.startswith(bridge) else dynamic_q
                self._current_question = HRQuestion(
                    id=f"hr-dynamic-{self.current_index}",
                    question=bridged_text,
                    category=base_q.category,
                    interview_style=self.interview_style,
                )
            else:
                styled = self._styled_question(base_q)
                bridged_text = f"{bridge} {styled}" if bridge else styled
                self._current_question = HRQuestion(
                    id=base_q.id,
                    question=bridged_text,
                    category=base_q.category,
                    interview_style=self.interview_style,
                )
        else:
            self._finished = True
            self._current_question = None

    def _adaptive_follow_up(self, question: HRQuestion, evaluation: HREvaluation) -> HRQuestion | None:
        """Selectively probe weak or inconsistent answers without creating an endless chain."""
        # Do not chain ordinary pressure probes. An unrelated/evasive reply to
        # a follow-up is the exception: a real interviewer explicitly brings
        # the candidate back once instead of silently changing the subject.
        if question.id.startswith("hr-followup-") and evaluation.follow_up_category != "Relevance clarification":
            return None
        max_followups = max(2, self.max_questions - 1)
        if self._followups_used >= max_followups or not evaluation.needs_follow_up:
            return None
        weak_signal = (
            evaluation.overall_score < 0.72
            or min(
                evaluation.specificity,
                evaluation.ownership,
                evaluation.communication,
                evaluation.problem_solving,
            ) < 0.68
            or evaluation.pressure_level >= 2
        )
        if not weak_signal and not evaluation.needs_follow_up:
            return None
        text = _safe_follow_up_text(evaluation.follow_up_question)
        if not text:
            return None
        category = evaluation.follow_up_category.strip() or evaluation.probe_focus.strip() or "Adaptive follow-up"
        return HRQuestion(
            id=f"hr-followup-{self.current_index}",
            question=text,
            category=category[:80],
            interview_style=self.interview_style,
        )

    def report(self) -> dict:
        if not self._started:
            raise ValueError("Cannot generate report: interview not started.")
        if not self._finished and self.current_index < self.max_questions:
            raise ValueError("Cannot generate report: interview not completed.")
        
        if not self.history:
            return {"overall_score": 0.0, "summary": "No questions answered."}
        
        avg_score = sum(ev.overall_score for _, _, ev in self.history) / len(self.history)
        
        metrics = {
            "clarity": sum(ev.clarity for _, _, ev in self.history) / len(self.history),
            "specificity": sum(ev.specificity for _, _, ev in self.history) / len(self.history),
            "ownership": sum(ev.ownership for _, _, ev in self.history) / len(self.history),
            "communication": sum(ev.communication for _, _, ev in self.history) / len(self.history),
            "teamwork": sum(ev.teamwork for _, _, ev in self.history) / len(self.history),
            "leadership": sum(ev.leadership for _, _, ev in self.history) / len(self.history),
            "problem_solving": sum(ev.problem_solving for _, _, ev in self.history) / len(self.history),
        }
        
        sorted_metrics = sorted(metrics.items(), key=lambda x: x[1])
        strengths = [k for k, v in sorted_metrics[-2:]]
        weaknesses = [k for k, v in sorted_metrics[:2]]
        
        return {
            "overall_score": round(avg_score, 3),
            "questions_answered": len(self.history),
            "metrics": {k: round(v, 3) for k, v in metrics.items()},
            "strengths": strengths,
            "weaknesses": weaknesses,
            "interview_signals": [
                {
                    "question_id": q.id,
                    "probe_focus": ev.probe_focus,
                    "pressure_level": ev.pressure_level,
                    "observed_signal": ev.observed_signal,
                    "follow_up_used": q.id.startswith("hr-followup-"),
                }
                for q, _, ev in self.history
                if ev.observed_signal or ev.probe_focus
            ],
            "feedback_summary": [
                {
                    "question_id": q.id,
                    "category": q.category,
                    "score": round(ev.overall_score, 3),
                    "feedback": ev.feedback
                } for q, _, ev in self.history
            ]
        }
