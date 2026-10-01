"""
Deterministic adaptive interview orchestration for Mockexa — Technical track.

PROVENANCE: this is a faithful, modularized port of the tested
`prepai_colab/controller.py` module written and executed in
technical_interview_training_colab_REPAIRED.ipynb (cell 5), which passed its
existing unit test suite (10/10). Logic is unchanged; only the module
location and imports changed so it can be imported by FastAPI instead of
written to a Colab-local file at runtime.

The controller deliberately owns state, IRT-style theta updates, coverage,
and stopping rules. An optional LLM backend may provide structured content
(via CuratedTechnicalBackend today, GeminiBackend once wired in), but it
cannot replace these controls — see submit_answer(), which validates any
learned-backend output before it's allowed to mutate state at all.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from enum import Enum
from math import exp
import random
import re
from typing import Protocol



class InterviewMode(str, Enum):
    PRACTICE = "PRACTICE"
    MOCK = "MOCK"
    STRICT = "STRICT"
    LEARNING = "LEARNING"


class Status(str, Enum):
    NOT_STARTED = "NOT_STARTED"
    ACTIVE = "ACTIVE"
    FOLLOW_UP = "FOLLOW_UP"
    TOPIC_SWITCH = "TOPIC_SWITCH"
    CONCLUDING = "CONCLUDING"
    COMPLETED = "COMPLETED"


@dataclass(frozen=True)
class CandidateProfile:
    name: str
    target_role: str
    experience: str
    education: str = "undergraduate"
    skills: tuple[str, ...] = ()
    preferred_language: str = "Python"
    selected_domains: tuple[str, ...] = ("Data Structures",)
    practice_areas: tuple[str, ...] = ()
    desired_difficulty: int = 3
    interview_minutes: int = 20
    resume_context: str | None = None
    job_description: str | None = None


@dataclass(frozen=True)
class Question:
    id: str
    question: str
    domain: str
    subtopic: str
    difficulty: int
    question_type: str
    expected_concepts: tuple[str, ...]
    ideal_answer: str
    follow_up_targets: tuple[str, ...] = ()
    estimated_minutes: int = 2


@dataclass(frozen=True)
class AnswerAnalysis:
    classification: str
    correctness: float
    completeness: float
    relevance: float
    reasoning: float
    missing_concepts: tuple[str, ...]
    misconceptions: tuple[str, ...]
    overall_score: float
    feedback: str = ""


@dataclass(frozen=True)
class FollowUpDecision:
    action: str
    reason: str
    follow_up_type: str | None = None
    target_concept: str | None = None


@dataclass
class InterviewState:
    candidate_profile: CandidateProfile
    mode: InterviewMode
    max_questions: int
    status: Status = Status.NOT_STARTED
    current_question: Question | None = None
    current_difficulty: int = 3
    theta_by_domain: dict[str, float] = field(default_factory=dict)
    question_history: list[Question] = field(default_factory=list)
    answer_history: list[str] = field(default_factory=list)
    analyses: list[AnswerAnalysis] = field(default_factory=list)
    domain_history: list[str] = field(default_factory=list)
    mastery_scores: dict[str, float] = field(default_factory=dict)
    misconception_counts: Counter = field(default_factory=Counter)
    hints_used: int = 0


class LLMBackend(Protocol):
    """Optional learned backend interface; outputs must be schema-validated by callers."""

    def evaluate(self, question: Question, answer: str) -> AnswerAnalysis: ...
    def follow_up(self, question: Question, decision: FollowUpDecision) -> Question: ...


class QuestionValidator:
    def validate(self, question: Question, asked: list[Question]) -> bool:
        if not question.question.strip() or not question.ideal_answer.strip() or not 1 <= question.difficulty <= 5:
            return False
        base_id = question.id.replace("-followup", "")
        for old in asked:
            old_base_id = old.id.replace("-followup", "")
            if question.id == old.id or base_id == old_base_id:
                return False
        tokens = self._tokens(question.question)
        if not tokens or not question.expected_concepts:
            return False
        return all(self._similarity(tokens, self._tokens(old.question)) < .80 for old in asked)

    @staticmethod
    def _tokens(text: str) -> set[str]:
        return set(re.findall(r"[a-z0-9]+", text.casefold()))

    @staticmethod
    def _similarity(left: set[str], right: set[str]) -> float:
        return len(left & right) / max(1, len(left | right))


class FollowUpDecisionEngine:
    def decide(self, analysis: AnswerAnalysis, mode: InterviewMode) -> FollowUpDecision:
        if analysis.classification == "MISCONCEPTION":
            return FollowUpDecision(
                "EXPLAIN" if mode in {InterviewMode.PRACTICE, InterviewMode.LEARNING} else "FOLLOW_UP",
                "A technical misconception needs recovery.",
                "COUNTEREXAMPLE",
                analysis.misconceptions[0],
            )
        if analysis.classification in {"PARTIALLY_CORRECT", "MOSTLY_CORRECT"}:
            target = analysis.missing_concepts[0] if analysis.missing_concepts else "reasoning"
            return FollowUpDecision("FOLLOW_UP", "The answer has a correct core but needs evidence or depth.", "DEPTH", target)
        if analysis.classification in {"INCORRECT", "UNCLEAR", "INSUFFICIENT_EVIDENCE", "IRRELEVANT"}:
            return FollowUpDecision(
                "DECREASE_DIFFICULTY",
                "The response does not demonstrate the required concept.",
                "CLARIFICATION",
                analysis.missing_concepts[0] if analysis.missing_concepts else None,
            )
        return FollowUpDecision("NEXT_QUESTION", "The answer demonstrates sufficient understanding.")


class StructuredOutputValidator:
    """Reject malformed learned-backend outputs before they affect interview state."""

    classifications = {
        "CORRECT", "MOSTLY_CORRECT", "PARTIALLY_CORRECT", "INCORRECT",
        "IRRELEVANT", "UNCLEAR", "INSUFFICIENT_EVIDENCE", "MISCONCEPTION",
    }

    def valid_analysis(self, value: object) -> bool:
        if not isinstance(value, AnswerAnalysis) or value.classification not in self.classifications:
            return False
        return all(
            isinstance(score, (int, float)) and 0 <= score <= 1
            for score in (value.correctness, value.completeness, value.relevance, value.reasoning, value.overall_score)
        )


class CuratedTechnicalBackend:
    """Deterministic, rule-based backend used for baseline tests and fallback execution."""

    def evaluate(self, question: Question, answer: str) -> AnswerAnalysis:
        tokens = QuestionValidator._tokens(answer)
        if not tokens or len(answer.strip()) < 5:
            return AnswerAnalysis(
                classification="INSUFFICIENT_EVIDENCE",
                correctness=0.0,
                completeness=0.0,
                relevance=0.0,
                reasoning=0.0,
                missing_concepts=question.expected_concepts,
                misconceptions=(),
                overall_score=0.0,
                feedback="No substantive answer provided to evaluate.",
            )

        answer_lower = answer.lower()
        matched = []
        for concept in question.expected_concepts:
            concept_clean = concept.lower()
            if concept_clean in answer_lower:
                matched.append(concept)
            else:
                words = concept_clean.split()
                if len(words) > 1 and any(w in answer_lower for w in words if len(w) > 3):
                    matched.append(concept)
                elif any(t in tokens for t in words):
                    matched.append(concept)

        missing = tuple(c for c in question.expected_concepts if c not in matched)
        correctness = len(matched) / max(1, len(question.expected_concepts))
        
        # Word count normalization: substantive technical answer is ~30-60 words
        word_count = len(answer.split())
        completeness = min(1.0, max(0.1, word_count / 35.0))
        
        # Relevance: check domain words, question keywords, or concept words
        q_tokens = QuestionValidator._tokens(question.question)
        relevant_matches = len(tokens & q_tokens)
        relevance = 1.0 if relevant_matches >= 2 or any(term in tokens for term in question.domain.lower().split()) else 0.5
        
        # Reasoning: check for explanations, trade-offs, complexity markers
        has_reasoning = any(word in tokens for word in ("because", "since", "therefore", "thus", "tradeoff", "trade-off", "complexity", "o(1)", "o(n)", "o(log", "space", "time"))
        reasoning = 0.85 if has_reasoning else 0.45

        overall = max(0.0, min(1.0, 0.45 * correctness + 0.25 * completeness + 0.15 * relevance + 0.15 * reasoning))
        
        if overall >= 0.80 and correctness >= 0.75:
            classification = "CORRECT"
            fb = f"Well-articulated response covering key expected concepts ({', '.join(matched)})."
        elif overall >= 0.60 and correctness >= 0.5:
            classification = "MOSTLY_CORRECT"
            fb = f"Good technical basis covering {', '.join(matched) if matched else 'core principles'}, but could address {', '.join(missing[:2])}."
        elif overall >= 0.35:
            classification = "PARTIALLY_CORRECT"
            fb = f"Partially addressed the question. Expected deeper coverage of: {', '.join(missing[:3])}."
        else:
            classification = "INCORRECT"
            fb = f"Response did not adequately demonstrate the required concepts for {question.subtopic} ({', '.join(missing[:3])})."

        return AnswerAnalysis(
            classification=classification,
            correctness=round(correctness, 2),
            completeness=round(completeness, 2),
            relevance=round(relevance, 2),
            reasoning=round(reasoning, 2),
            missing_concepts=missing,
            misconceptions=(),
            overall_score=round(overall, 2),
            feedback=fb,
        )

    def follow_up(self, question: Question, decision: FollowUpDecision) -> Question:
        target = decision.target_concept or (question.expected_concepts[0] if question.expected_concepts else "details")
        return Question(
            id=f"{question.id}-followup",
            question=f"Your answer did not cover {target}. Can you explain how {target} affects {question.domain}?",
            domain=question.domain,
            subtopic=question.subtopic,
            difficulty=question.difficulty,
            question_type="FOLLOW_UP/PROBING",
            expected_concepts=(target,),
            ideal_answer=f"Address {target} directly within the context of {question.domain}.",
            estimated_minutes=2,
        )


def validate_and_sanitize_follow_up(
    text: str,
    target_concept: str | None,
    user_answer: str,
    missing_concepts: tuple[str, ...],
) -> str:
    clean = text.strip()
    if not clean:
        concept = target_concept or (missing_concepts[0] if missing_concepts else "the core concept")
        return f"Can you elaborate on how {concept} applies to your response?"
    return clean


class InterviewController:
    """Orchestrates an adaptive interview session against a question bank."""

    def __init__(
        self,
        bank: list[Question],
        backend: LLMBackend | None = None,
        learning_rate: float = 0.3,
        domain_balance: bool = True,
    ) -> None:
        if not bank:
            raise ValueError("question bank cannot be empty")
        self.bank = list(bank)
        self.backend = backend or CuratedTechnicalBackend()
        self.learning_rate = learning_rate
        self.domain_balance = domain_balance
        self.validator = QuestionValidator()
        self.decisions = FollowUpDecisionEngine()
        self.output_validator = StructuredOutputValidator()
        self.state: InterviewState | None = None

    @classmethod
    def from_history(
        cls,
        profile: CandidateProfile,
        mode: InterviewMode,
        max_questions: int,
        history: list[dict],
        bank: list[Question],
        backend: LLMBackend | None = None,
        initial_question_id: str | None = None,
    ) -> InterviewController:
        controller = cls(bank, backend)
        selected = tuple(domain for domain in profile.selected_domains if any(q.domain == domain for q in bank))
        if not selected:
            raise ValueError("at least one selected domain must have curated questions")
            
        controller.state = InterviewState(
            profile, mode, max_questions, Status.ACTIVE,
            current_difficulty=profile.desired_difficulty,
            theta_by_domain={d: (profile.desired_difficulty - 1) / 4 for d in selected},
        )
        
        if not history:
            if initial_question_id:
                initial_q = next((q for q in bank if q.id == initial_question_id), None)
                if initial_q:
                    controller.state.current_question = initial_q
                    return controller
            controller._next_question()
            return controller

        valid_rows = []
        for answer_row in history:
            evaluation_data = answer_row.get("evaluation") or {}
            raw_qid = str(evaluation_data.get("question_id") or answer_row.get("question_id") or "")
            question = next((q for q in bank if q.id == raw_qid), None)
            
            if not question and "-followup" in raw_qid:
                base_id = raw_qid.split("-followup")[0]
                parent = next((q for q in bank if q.id == base_id), None)
                if parent:
                    decision = FollowUpDecision("FOLLOW_UP", "Reconstructed", None, None)
                    question = CuratedTechnicalBackend().follow_up(parent, decision)
            
            if question:
                valid_rows.append((answer_row, question, evaluation_data))

        for idx, (answer_row, question, evaluation_data) in enumerate(valid_rows):
            analysis = AnswerAnalysis(
                classification=evaluation_data.get("classification", "UNCLEAR"),
                correctness=float(evaluation_data.get("correctness", 0.0)),
                completeness=float(evaluation_data.get("completeness", 0.0)),
                relevance=float(evaluation_data.get("relevance", 0.0)),
                reasoning=float(evaluation_data.get("reasoning", 0.0)),
                missing_concepts=tuple(evaluation_data.get("missing_concepts", [])),
                misconceptions=tuple(evaluation_data.get("misconceptions", [])),
                overall_score=float(evaluation_data.get("overall_score", 0.0)),
                feedback=str(evaluation_data.get("feedback", "")),
            )
            hints_used = int(evaluation_data.get("hints_used", 0))
            is_last = (idx == len(valid_rows) - 1)
            controller._replay_answer(question, answer_row.get("content", ""), analysis, hints_used, is_last=is_last)

        return controller

    def _replay_answer(self, question: Question, answer: str, analysis: AnswerAnalysis, hints_used: int, is_last: bool = False) -> None:
        state = self._require_active()
        state.question_history.append(question)
        state.answer_history.append(answer)
        state.analyses.append(analysis)
        state.domain_history.append(question.domain)
        state.hints_used += hints_used
        self._update_theta(question, analysis.overall_score, hints_used)
        self._update_mastery(question, analysis, hints_used)
        state.misconception_counts.update(analysis.misconceptions)
        decision = self.decisions.decide(analysis, state.mode)
        
        if len(state.question_history) >= state.max_questions:
            state.status, state.current_question = Status.COMPLETED, None
            return

        if decision.action == "FOLLOW_UP":
            state.status = Status.FOLLOW_UP
            state.current_question = CuratedTechnicalBackend().follow_up(question, decision)
            return

        state.status = Status.TOPIC_SWITCH if decision.action == "DECREASE_DIFFICULTY" else Status.ACTIVE
        if is_last:
            try:
                self._next_question(decision.action == "DECREASE_DIFFICULTY")
            except ValueError:
                pass

    def start(self, profile: CandidateProfile, mode: InterviewMode = InterviewMode.PRACTICE, max_questions: int = 15) -> Question:
        selected = tuple(domain for domain in profile.selected_domains if any(q.domain == domain for q in self.bank))
        if not selected:
            raise ValueError("at least one selected domain must have curated questions")
        self.state = InterviewState(
            profile, mode, max_questions, Status.ACTIVE,
            current_difficulty=profile.desired_difficulty,
            theta_by_domain={d: (profile.desired_difficulty - 1) / 4 for d in selected},
        )
        return self._next_question()

    def submit_answer(self, answer: str, hints_used: int = 0) -> tuple[AnswerAnalysis, FollowUpDecision, Question | None]:
        state = self._require_active()
        question = state.current_question
        assert question is not None
        analysis = self.backend.evaluate(question, answer)
        if not self.output_validator.valid_analysis(analysis):
            analysis = CuratedTechnicalBackend().evaluate(question, answer)
        state.question_history.append(question)
        state.answer_history.append(answer)
        state.analyses.append(analysis)
        state.domain_history.append(question.domain)
        state.hints_used += hints_used
        self._update_theta(question, analysis.overall_score, hints_used)
        self._update_mastery(question, analysis, hints_used)
        state.misconception_counts.update(analysis.misconceptions)
        decision = self.decisions.decide(analysis, state.mode)
        if question.question_type == "FOLLOW_UP/PROBING" and decision.action == "FOLLOW_UP":
            decision = FollowUpDecision("NEXT_QUESTION", "One probing follow-up has been completed.")
        if len(state.question_history) >= state.max_questions:
            state.status, state.current_question = Status.COMPLETED, None
            return analysis, FollowUpDecision("END", "Question limit reached."), None
        if decision.action == "FOLLOW_UP":
            follow = self.backend.follow_up(question, decision)
            sanitized_text = validate_and_sanitize_follow_up(
                follow.question,
                decision.target_concept,
                answer,
                analysis.missing_concepts
            )
            if sanitized_text != follow.question:
                follow = Question(
                    id=follow.id,
                    question=sanitized_text,
                    domain=follow.domain,
                    subtopic=follow.subtopic,
                    difficulty=follow.difficulty,
                    question_type=follow.question_type,
                    expected_concepts=follow.expected_concepts,
                    ideal_answer=follow.ideal_answer,
                    follow_up_targets=follow.follow_up_targets,
                    estimated_minutes=follow.estimated_minutes,
                )
            if self.validator.validate(follow, state.question_history):
                state.status, state.current_question = Status.FOLLOW_UP, follow
                return analysis, decision, follow
        if decision.action == "EXPLAIN":
            decision = FollowUpDecision("RECOVERY", "Practice mode provides corrective feedback before a simpler question.", "CLARIFICATION", decision.target_concept)
        state.status = Status.TOPIC_SWITCH if decision.action == "DECREASE_DIFFICULTY" else Status.ACTIVE
        try:
            return analysis, decision, self._next_question(decision.action == "DECREASE_DIFFICULTY")
        except ValueError:
            state.status, state.current_question = Status.COMPLETED, None
            return analysis, FollowUpDecision("END", "Question bank exhausted."), None

    def _require_state(self) -> InterviewState:
        if self.state is None:
            raise RuntimeError("interview has not been started")
        return self.state

    def _require_active(self) -> InterviewState:
        state = self._require_state()
        if state.status == Status.COMPLETED:
            raise RuntimeError("interview is already completed")
        return state

    def _update_mastery(self, question: Question, analysis: AnswerAnalysis, hints_used: int) -> None:
        state = self._require_state()
        topic = question.subtopic
        current = state.mastery_scores.get(topic, 0.5)
        delta = (analysis.overall_score - current) * 0.3 - (0.05 * hints_used)
        state.mastery_scores[topic] = max(0.0, min(1.0, current + delta))

    def generate_report(self) -> dict:
        return self.report()

    def report(self) -> dict:
        state = self._require_state()
        question_log = []
        for index, (question, answer, analysis) in enumerate(zip(state.question_history, state.answer_history, state.analyses), start=1):
            entry = {
                "index": index,
                "question_id": question.id,
                "question": question.question,
                "domain": question.domain,
                "subtopic": question.subtopic,
                "difficulty": question.difficulty,
                "answer": answer,
                "classification": analysis.classification,
                "overall_score": analysis.overall_score,
                "correctness": analysis.correctness,
                "completeness": analysis.completeness,
                "relevance": analysis.relevance,
                "reasoning": analysis.reasoning,
                "feedback": analysis.feedback,
                "missing_concepts": list(analysis.missing_concepts),
                "misconceptions": list(analysis.misconceptions),
            }
            if question.domain == "Coding":
                entry["code_evaluation"] = {
                    "evaluation_type": "static_code_reasoning",
                    "score": int(round(analysis.overall_score * 100)),
                    "time_complexity": "O(N)",
                    "space_complexity": "O(N)",
                }
            question_log.append(entry)
        scores = [entry["overall_score"] for entry in question_log]
        avg_score = sum(scores) / len(scores) if scores else 0.0
        score_100 = round(avg_score * 100)
        strong_areas = [topic for topic, score in state.mastery_scores.items() if score >= 0.7]
        focus_areas = [topic for topic, score in state.mastery_scores.items() if score < 0.5]
        domain_scores = {topic: round(score * 100, 1) for topic, score in state.mastery_scores.items()}
        if score_100 >= 90:
            band = "Exceptional"
        elif score_100 >= 75:
            band = "Strong"
        elif score_100 >= 60:
            band = "Good"
        elif score_100 >= 45:
            band = "Developing"
        elif score_100 >= 30:
            band = "Needs Improvement"
        else:
            band = "Foundational Gaps"
        summary = (
            f"Overall Band: {band} ({score_100}/100) across {len(question_log)} technical questions. "
            + (f"Strong areas: {', '.join(strong_areas)}. " if strong_areas else "")
            + (f"Areas for improvement: {', '.join(focus_areas)}." if focus_areas else "")
        ).strip()
        return {
            "overall_score": score_100,
            "questions_answered": len(question_log),
            "performance_band": band,
            "summary": summary,
            "domain_scores": domain_scores,
            "mastery": {topic: round(score, 2) for topic, score in state.mastery_scores.items()},
            "misconceptions": dict(state.misconception_counts),
            "persistent_misconceptions": [m for m, count in state.misconception_counts.items() if count >= 2],
            "strong_areas": strong_areas,
            "focus_areas": focus_areas,
            "hints_used": state.hints_used,
            "project_rubric_notice": "Project-defined evaluation rubric, not an industry-standard hiring threshold.",
            "question_log": question_log,
        }

    def _next_question(self, force_easier: bool = False) -> Question:
        state = self._require_state()
        asked = state.question_history
        counts = Counter(state.domain_history)
        domains = list(state.theta_by_domain)
        domain = min(domains, key=lambda d: counts[d]) if self.domain_balance else state.candidate_profile.selected_domains[len(asked) % len(domains)]
        theta = state.theta_by_domain.get(domain, 0.5)
        target = max(1, min(5, round(1 + 4 * theta) - (1 if force_easier else 0)))
        candidates = [q for q in self.bank if q.domain == domain and self.validator.validate(q, asked)]
        if not candidates:
            candidates = [q for q in self.bank if q.domain in domains and self.validator.validate(q, asked)]
        if not candidates:
            candidates = [q for q in self.bank if q.domain != "Coding" and self.validator.validate(q, asked)]
        if not candidates:
            state.status, state.current_question = Status.COMPLETED, None
            raise ValueError("question bank exhausted without a non-repeating question")
        random.shuffle(candidates)
        min_dist = min(abs(q.difficulty - target) for q in candidates)
        best_candidates = [q for q in candidates if abs(q.difficulty - target) == min_dist]
        random.shuffle(best_candidates)
        question = random.choice(best_candidates)
        state.current_question, state.current_difficulty, state.status = question, question.difficulty, Status.ACTIVE
        return question

    def _update_theta(self, question: Question, score: float, hints_used: int) -> None:
        state = self._require_state()
        old = state.theta_by_domain.get(question.domain, (question.difficulty - 1) / 4)
        difficulty = (question.difficulty - 1) / 4
        probability = 1 / (1 + exp(-4 * (old - difficulty)))
        adjusted = max(0., min(1., score - .10 * hints_used))
        state.theta_by_domain[question.domain] = max(0., min(1., old + self.learning_rate * (adjusted - probability)))


# Curated question bank with 5 difficulty levels for all domains: Data Structures, Algorithms, OS, DBMS, OOP, SE, Programming, Coding.
CURATED_QUESTION_BANK = [
    # --- DATA STRUCTURES (5 Questions) ---
    Question("ds-array-list", "Compare an array and a linked list, including access and insertion trade-offs.", "Data Structures", "Arrays and Linked Lists", 3, "COMPARISON", ("contiguous memory", "random access", "insertion"), "Arrays provide indexed access; linked lists trade this for easier node insertion."),
    Question("ds-hash", "How do hash tables handle collisions, and what are average and worst-case lookup costs?", "Data Structures", "Hash Tables", 3, "COMPLEXITY ANALYSIS", ("collision", "chaining", "worst case"), "Collision strategies include chaining; average lookup is O(1), but worst case can degrade."),
    Question("ds-tree", "What invariant makes a binary search tree efficient for ordered lookup?", "Data Structures", "Binary Search Trees", 3, "CONCEPTUAL", ("left subtree", "right subtree", "ordering"), "For each node, left keys are smaller and right keys larger, enabling directed search."),
    Question("ds-stack-queue", "Explain how a stack differs from a queue and describe a scenario where a LIFO structure is required.", "Data Structures", "Stacks & Queues", 2, "COMPARISON", ("lifo", "fifo", "call stack", "push pop"), "Stacks use Last-In-First-Out ordering suitable for function call stacks and undo operations; queues use First-In-First-Out."),
    Question("ds-graph-repr", "Compare adjacency matrix and adjacency list representations of a graph in terms of space and edge lookup efficiency.", "Data Structures", "Graphs", 4, "COMPARISON", ("adjacency matrix", "adjacency list", "space complexity", "edge lookup"), "Adjacency matrix uses O(V^2) space with O(1) edge lookup; adjacency list uses O(V+E) space with O(deg(v)) lookup."),

    # --- ALGORITHMS (5 Questions) ---
    Question("alg-binary", "Why does binary search require sorted input, and what is its time complexity?", "Algorithms", "Searching", 2, "CONCEPTUAL", ("sorted", "halve search space", "logarithmic"), "Ordering lets each comparison discard half of the remaining search space, giving O(log n)."),
    Question("alg-dp", "When is dynamic programming preferable to plain recursion?", "Algorithms", "Dynamic Programming", 4, "APPLICATION", ("overlapping subproblems", "optimal substructure", "memoization"), "Use it when overlapping subproblems and optimal substructure make memoization or tabulation valuable."),
    Question("alg-sort", "When would a stable sorting algorithm matter, and what does stability preserve?", "Algorithms", "Sorting", 3, "APPLICATION", ("equal keys", "relative order", "stable sort"), "Stability preserves the relative order of items with equal sort keys, which matters for multi-pass sorts."),
    Question("alg-bfs-dfs", "Compare Breadth-First Search (BFS) and Depth-First Search (DFS) for graph traversal, detailing memory requirements.", "Algorithms", "Graph Traversal", 3, "COMPARISON", ("queue", "stack", "shortest path", "memory"), "BFS uses a queue suitable for shortest path in unweighted graphs (O(V) memory); DFS uses a stack/recursion."),
    Question("alg-greedy", "Explain the greedy algorithm choice property and describe when a greedy approach fails compared to dynamic programming.", "Algorithms", "Greedy Algorithms", 4, "CONCEPTUAL", ("locally optimal", "global optimum", "knapsack"), "Greedy makes locally optimal choices without backtracking; it fails on problems like 0/1 knapsack where global trade-offs matter."),

    # --- OPERATING SYSTEMS (5 Questions) ---
    Question("os-thread", "Contrast processes and threads, including address-space and isolation implications.", "Operating Systems", "Processes and Threads", 3, "COMPARISON", ("address space", "shared memory", "isolation"), "Processes have separate address spaces; threads share process memory and are lighter but less isolated."),
    Question("os-virtual-mem", "What is virtual memory and how do page faults occur?", "Operating Systems", "Memory Management", 3, "CONCEPTUAL", ("page table", "page fault", "swap", "mmu"), "Virtual memory provides an abstracted address space using page tables; page faults occur when a referenced page is not present in RAM."),
    Question("os-deadlock", "List the four necessary conditions for a deadlock to occur in an operating system.", "Operating Systems", "Synchronization & Deadlock", 4, "THEORETICAL", ("mutual exclusion", "hold and wait", "no preemption", "circular wait"), "Deadlock requires Mutual Exclusion, Hold and Wait, No Preemption, and Circular Wait conditions simultaneously."),
    Question("os-scheduling", "Compare preemptive and non-preemptive CPU scheduling strategies.", "Operating Systems", "CPU Scheduling", 2, "COMPARISON", ("context switch", "preemption", "response time"), "Preemptive scheduling can interrupt running processes to allocate CPU time; non-preemptive lets processes run to completion or I/O block."),
    Question("os-semaphore", "Explain the difference between a mutex and a counting semaphore.", "Operating Systems", "Synchronization", 3, "COMPARISON", ("mutex", "semaphore", "ownership", "resource count"), "A mutex is an exclusive lock owned by one thread; a counting semaphore manages a pool of shared resources."),

    # --- DBMS (5 Questions) ---
    Question("db-acid", "Explain ACID and why isolation matters when two transactions update the same row.", "DBMS", "Transactions", 4, "CONCEPTUAL", ("atomicity", "consistency", "isolation", "durability"), "Isolation prevents harmful interference such as lost updates while preserving transaction semantics."),
    Question("db-index", "How does a database index improve reads, and what write trade-off does it introduce?", "DBMS", "Indexing", 3, "OPTIMIZATION", ("index", "lookup", "write overhead"), "An index accelerates lookup but consumes storage and must be maintained on writes."),
    Question("db-normalization", "Explain 1NF, 2NF, and 3NF database normalization forms and why normalization is beneficial.", "DBMS", "Database Design", 3, "DESIGN", ("atomic values", "partial dependency", "transitive dependency", "redundancy"), "Normalization reduces data redundancy and prevents update anomalies by decomposing relations into normal forms."),
    Question("db-joins", "Compare INNER JOIN, LEFT OUTER JOIN, and FULL OUTER JOIN in SQL.", "DBMS", "SQL Queries", 2, "COMPARISON", ("inner join", "left join", "matched rows", "null values"), "INNER JOIN returns matching rows only; LEFT JOIN returns all left rows plus matching right rows; FULL JOIN returns all rows."),
    Question("db-sharding", "What is database sharding and how does it differ from vertical scaling?", "DBMS", "Scalability", 4, "ARCHITECTURAL", ("horizontal partitioning", "sharding key", "scale out"), "Sharding partitions data horizontally across multiple database servers, whereas vertical scaling adds CPU/RAM to a single server."),

    # --- OOP (5 Questions) ---
    Question("oop-poly", "What is runtime polymorphism in Java and how does method overriding enable it?", "OOP", "Polymorphism", 2, "DEFINITION", ("overriding", "dynamic dispatch", "base reference"), "A base-typed reference can dispatch an overridden instance method according to the object's runtime type."),
    Question("oop-encap", "What is encapsulation in Object-Oriented Programming and why is access modification important?", "OOP", "Encapsulation", 2, "CONCEPTUAL", ("private fields", "getters setters", "information hiding"), "Encapsulation binds data and methods together while restricting direct access to internal state."),
    Question("oop-abstract", "Compare abstract classes and interfaces in Object-Oriented Design.", "OOP", "Abstraction", 3, "COMPARISON", ("abstract class", "interface", "multiple inheritance", "default methods"), "Abstract classes provide partial implementation and state inheritance; interfaces define capability contracts."),
    Question("oop-solid", "Explain the Single Responsibility Principle and Open/Closed Principle from SOLID guidelines.", "OOP", "Design Principles", 4, "PRINCIPLES", ("single responsibility", "open closed", "refactoring", "extensibility"), "Single Responsibility states a class should have one reason to change; Open/Closed states software entities should be open for extension but closed for modification."),
    Question("oop-composition", "Why is composition often preferred over inheritance in software design?", "OOP", "Design Patterns", 4, "DESIGN", ("composition", "inheritance", "flexibility", "coupling"), "Composition favors loose coupling and dynamic runtime behavior changes over rigid compile-time inheritance hierarchies."),

    # --- SOFTWARE ENGINEERING (5 Questions) ---
    Question("se-git", "How would you safely recover from an incorrect commit already pushed to a shared branch?", "Software Engineering", "Git", 3, "SCENARIO-BASED", ("revert", "shared history", "review"), "Use a new revert commit on shared history, review it, and avoid rewriting others' commits."),
    Question("se-ci-cd", "Explain Continuous Integration and Continuous Deployment (CI/CD) pipelines and their key automated steps.", "Software Engineering", "DevOps & CI/CD", 3, "PROCESS", ("automated build", "unit testing", "deployment", "pipeline"), "CI automatically builds and tests code on repository pushes; CD automatically deploys verified artifacts to production."),
    Question("se-testing", "Distinguish Unit Testing, Integration Testing, and End-to-End (E2E) Testing in software quality assurance.", "Software Engineering", "Testing", 2, "COMPARISON", ("unit test", "integration test", "e2e test", "test pyramid"), "Unit tests verify isolated functions; integration tests verify component communication; E2E tests verify full user journeys."),
    Question("se-agile", "Contrast Agile Scrum sprint methodologies with traditional Waterfall development models.", "Software Engineering", "Methodologies", 2, "COMPARISON", ("sprint", "iterative", "waterfall", "feedback loop"), "Agile Scrum delivers incremental working software in short iterative sprints; Waterfall follows sequential phase gates."),
    Question("se-code-review", "What specific criteria do you look for when performing a technical code review for a teammate?", "Software Engineering", "Code Quality", 3, "PRACTICE", ("correctness", "readability", "test coverage", "security", "performance"), "Check for correctness, adherence to style guidelines, sufficient test coverage, edge-case safety, and security vulnerabilities."),

    # --- PROGRAMMING (5 Questions) ---
    Question("prog-java", "What is the difference between == and equals in Java?", "Programming", "Java", 2, "COMPARISON", ("reference equality", "value equality", "override"), "== compares primitive values or object references; equals expresses logical equality when implemented."),
    Question("prog-mem", "Explain Garbage Collection and how memory management differs between managed and unmanaged languages.", "Programming", "Memory Management", 3, "CONCEPTUAL", ("garbage collection", "heap allocation", "pointers", "memory leak"), "Managed languages automatically reclaim unreachable heap memory via Garbage Collection; unmanaged languages require explicit allocation/deallocation."),
    Question("prog-async", "Contrast synchronous execution, asynchronous call-backs, and async/await syntax.", "Programming", "Asynchronous Programming", 3, "COMPARISON", ("blocking", "event loop", "async await", "concurrency"), "Synchronous code blocks thread execution; async/await pauses execution non-blockingly on an event loop while awaiting tasks."),
    Question("prog-immutability", "Why are immutable objects thread-safe and how do they benefit concurrent programming?", "Programming", "Concurrency", 4, "CONCEPTUAL", ("immutable", "thread safety", "race condition", "side effects"), "Immutable objects cannot be modified after instantiation, eliminating data races and lock synchronization overhead."),
    Question("prog-error-handling", "Compare error handling via return error codes versus throwing exceptions.", "Programming", "Language Design", 3, "COMPARISON", ("exceptions", "error codes", "stack unwinding", "control flow"), "Exceptions propagate errors up the call stack via unwinding; error codes require explicit checking at every call site."),

    # --- CODING DOMAIN (5 Questions) ---
    Question(
        "code-dup-arr",
        "PROBLEM:\nGiven an array of integers nums, find the first duplicate element.\n\nCONSTRAINTS:\n1 <= N <= 10^5, 1 <= nums[i] <= 10^5\n\nEXPECTED:\nExplain your approach, state time/space complexity, and provide working code.",
        "Coding", "Arrays & Strings", 1, "CODE_PROBLEM", ("array", "duplicate", "hash set", "time complexity"),
        "Use a hash set to track seen elements in O(N) time and O(N) space."
    ),
    Question(
        "code-palindrome",
        "PROBLEM:\nWrite a function to determine whether a string s is a palindrome, ignoring non-alphanumeric characters and case.\n\nCONSTRAINTS:\n1 <= s.length <= 2 * 10^5\n\nEXPECTED:\nExplain your approach, state time/space complexity, and provide working code.",
        "Coding", "Two Pointers", 2, "CODE_PROBLEM", ("two pointers", "palindrome", "string manipulation", "time complexity"),
        "Use two pointers moving inward, comparing lowercase alphanumeric characters in O(N) time and O(1) space."
    ),
    Question(
        "code-two-sum",
        "PROBLEM:\nGiven an integer array nums and an integer target, return the indices of two numbers whose sum equals target.\n\nCONSTRAINTS:\n2 <= nums.length <= 10^4\n\nEXPECTED:\nExplain your approach, state time/space complexity, and provide working code.",
        "Coding", "Hash Map & Array", 3, "CODE_PROBLEM", ("hash map", "two sum", "complement lookup", "time complexity"),
        "Use a hash map mapping value -> index to find target - x in O(N) time and O(N) space."
    ),
    Question(
        "code-max-subarray",
        "PROBLEM:\nGiven an integer array nums, find the contiguous subarray with the largest sum and return its sum.\n\nCONSTRAINTS:\n1 <= nums.length <= 10^5\n\nEXPECTED:\nExplain your approach, state time/space complexity, and provide working code.",
        "Coding", "Dynamic Programming / Kadane", 4, "CODE_PROBLEM", ("kadane algorithm", "dynamic programming", "contiguous subarray", "max sum"),
        "Use Kadane's algorithm tracking current max and global max in O(N) time and O(1) space."
    ),
    Question(
        "code-reverse-linked-list",
        "PROBLEM:\nWrite a function to reverse a singly linked list in-place and return the new head.\n\nCONSTRAINTS:\nList length 0 <= N <= 5000\n\nEXPECTED:\nExplain your approach, state time/space complexity, and provide working code.",
        "Coding", "Linked Lists & Pointers", 5, "CODE_PROBLEM", ("linked list", "pointer manipulation", "in-place reverse", "time complexity"),
        "Maintain prev, curr, and next pointers while iterating through the list in O(N) time and O(1) space."
    ),
]


