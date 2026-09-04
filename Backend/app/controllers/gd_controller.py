from __future__ import annotations

import math
import random
import re
from collections import Counter
from dataclasses import asdict, dataclass
import json
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from app.providers.model_router import ModelRouter

SEED = 42

@dataclass
class TopicAnalysis:
    topic: str
    main_topic: str
    central_question: str
    topic_type: List[str]
    key_entities: List[str]
    key_concepts: List[str]
    positive_dimensions: List[str]
    negative_dimensions: List[str]
    stakeholders: List[str]
    benefits: List[str]
    risks: List[str]
    arguments_for: List[str]
    arguments_against: List[str]
    controversial_points: List[str]
    assumptions: List[str]
    evidence_requirements: List[str]

class TopicAnalyzer:
    DOMAIN = {
        "ai": (
            "technology",
            ["AI developers", "users", "regulators", "workers", "researchers"],
            ["innovation", "accuracy", "scalability", "productivity"],
            ["bias", "safety", "accountability", "privacy"],
        ),
        "health": (
            "healthcare",
            ["patients", "clinicians", "hospitals", "insurers", "regulators"],
            ["access", "diagnostic speed", "capacity", "outcomes"],
            ["harm", "bias", "consent", "accountability"],
        ),
        "climate": (
            "environment",
            ["communities", "industry", "governments", "future generations", "scientists"],
            ["emissions reduction", "resilience", "health", "innovation"],
            ["cost", "inequality", "uncertainty", "implementation"],
        ),
        "government": (
            "policy",
            ["citizens", "governments", "businesses", "regulators", "civil society"],
            ["public benefit", "coordination", "fairness", "long-term stability"],
            ["bureaucracy", "overreach", "cost", "unequal enforcement"],
        ),
    }

    def analyze(self, topic: str) -> TopicAnalysis:
        clean = topic.strip().rstrip("?")
        low = clean.lower()
        hits = [v for k, v in self.DOMAIN.items() if k in low]
        types = list(dict.fromkeys([x[0] for x in hits] or ["social policy"]))
        stakeholders = list(
            dict.fromkeys(sum((x[1] for x in hits), []))
        ) or ["affected communities", "decision makers", "implementers"]
        benefits = list(dict.fromkeys(sum((x[2] for x in hits), []))) or [
            "effectiveness",
            "fairness",
            "social benefit",
        ]
        risks = list(dict.fromkeys(sum((x[3] for x in hits), []))) or [
            "unintended consequences",
            "cost",
            "equity concerns",
        ]
        tokens = [
            x
            for x in re.findall(r"[A-Za-z]{4,}", clean)
            if x.lower() not in {"should", "would", "could", "their", "highly", "even", "that", "this"}
        ]
        entities = list(dict.fromkeys(tokens))[:8]
        verb = "whether " + clean[0].lower() + clean[1:]
        return TopicAnalysis(
            topic,
            clean,
            verb,
            types,
            entities,
            entities[:6],
            benefits,
            risks,
            stakeholders,
            benefits,
            risks,
            [f"It can improve {b}" for b in benefits[:4]],
            [f"It may worsen {r}" for r in risks[:4]],
            [
                "who is accountable",
                "how benefits and harms are distributed",
                "what evidence threshold is sufficient",
            ],
            [
                "implementation is feasible",
                "outcomes can be measured",
                "stakeholders have meaningful input",
            ],
            [
                "comparative outcome studies",
                "subgroup impact analysis",
                "cost and implementation evidence",
            ],
        )

@dataclass
class PersonalityProfile:
    name: str
    role: str
    traits: List[str]
    communication_style: str
    expertise: str
    confidence: float
    risk_tolerance: float
    debate_style: str
    initial_position: float
    values: List[str]
    weaknesses: List[str]
    strengths: List[str]
    openness: float = 0.35

def default_profiles():
    return [
        PersonalityProfile(
            "Dr. Maya Shah", "Clinical statistician", ["analytical", "skeptical"],
            "precise and evidence-oriented", "risk analysis and statistics", 0.82, 0.25,
            "challenges unsupported claims", -0.35, ["safety", "accountability"],
            ["can overemphasize uncertainty"], ["careful inference"], 0.22
        ),
        PersonalityProfile(
            "Jordan Lee", "Public-interest ethicist", ["empathetic", "socially conscious"],
            "reflective and inclusive", "ethics and social policy", 0.73, 0.35,
            "centers affected people", -0.20, ["equity", "dignity", "participation"],
            ["may privilege fairness over speed"], ["stakeholder awareness"], 0.46
        ),
        PersonalityProfile(
            "Arjun Mehta", "AI entrepreneur", ["optimistic", "inventive"],
            "energetic and solution-focused", "technology and deployment", 0.78, 0.78,
            "builds on practical opportunities", 0.62, ["innovation", "access", "progress"],
            ["can underweight tail risks"], ["systems thinking"], 0.40
        ),
        PersonalityProfile(
            "Elena Ruiz", "Policy economist", ["pragmatic", "cost-conscious"],
            "clear and trade-off focused", "economics and regulation", 0.76, 0.52,
            "synthesizes incentives and feasibility", 0.18, ["feasibility", "efficiency", "fairness"],
            ["may compress moral nuance"], ["implementation analysis"], 0.35
        ),
    ]

@dataclass
class Argument:
    claim: str
    reasoning: str
    evidence_needed: str
    assumptions: str
    strength: float
    position: str
    issue: str
    speaker: str = ""
    round: int = 0

@dataclass
class Turn:
    speaker: str
    round: int
    action: str
    target: Optional[str]
    position: float
    claim: str
    response: str
    confidence: float
    argument: Argument
    counter_target: Optional[str] = None
    target_turn_index: Optional[int] = None

class SemanticMemory:
    def __init__(self, threshold=0.80):
        self.threshold = threshold
        self.claims = []

    def similarity(self, text):
        if not self.claims:
            return 0.0
        try:
            mat = TfidfVectorizer(stop_words="english").fit_transform(self.claims + [text])
            return float(cosine_similarity(mat[-1], mat[:-1]).max())
        except ValueError:
            return 0.0

    def is_novel(self, text):
        return self.similarity(text) < self.threshold

    def add(self, text):
        self.claims.append(text)

class ParticipantAgent:
    def __init__(self, profile, threshold=0.80):
        self.profile = profile
        self.position = profile.initial_position
        self.memory = SemanticMemory(threshold)
        self.arguments = []
        self.targets = []
        self.interactions = []
        self.position_history = [self.position]
        self.confidence = profile.confidence

    def decide(self, history, analysis, round_no, mode):
        recent = [t for t in history[-6:] if t.speaker != self.profile.name]
        opposed = [t for t in recent if t.position * self.position < -0.04]
        if mode == "consensus" and recent and round_no >= 3:
            return "SYNTHESIZE", recent[-1]
        if opposed and round_no > 1:
            return "COUNTERARGUE", max(opposed, key=lambda t: t.confidence)
        if recent and abs(self.position) < 0.18:
            return "CLARIFY", recent[-1]
        return "INTRODUCE_ARGUMENT", None

    def update_position(self, target_turn, own_argument):
        if not target_turn:
            self.position_history.append(self.position)
            return
        alignment = 1 if target_turn.position * self.position > 0 else -1
        impact = 0.06 * target_turn.confidence * self.profile.openness
        self.position = float(np.clip(self.position + alignment * impact, -1, 1))
        self.position_history.append(self.position)

def _clean_response_text(text: str, speaker_name: str | None = None) -> str:
    if not text:
        return ""
    cleaned = text.strip()
    
    preamble_patterns = [
        r"^\s*\*\*[^*:]+(?:\([^)]*\))?\*\*\s*:\s*",
        r"^\s*\*[^*:]+(?:\([^)]*\))?\*\s*:\s*",
        r"^\s*`[^`:]+`\s*:\s*",
        r"^\s*(?:\*\*)?(?:Dr\.|Prof\.|Mr\.|Ms\.|Mrs\.)?\s*[A-Z][a-zA-Z\s.'-]+\s*(?:\([^)]*\))?(?:\*\*)?\s*:\s*",
    ]
    for pat in preamble_patterns:
        cleaned = re.sub(pat, "", cleaned).strip()
        
    if speaker_name:
        escaped_speaker = re.escape(speaker_name)
        speaker_pat = r"^\s*(?:\*\*)?" + escaped_speaker + r"(?:\s*\([^)]*\))?(?:\*\*)?\s*:\s*"
        cleaned = re.sub(speaker_pat, "", cleaned, flags=re.IGNORECASE).strip()

    cleaned = re.sub(r"^\s*\*{1,2}\s*", "", cleaned).strip()

    if (cleaned.startswith('"') and cleaned.endswith('"')) or (cleaned.startswith("'") and cleaned.endswith("'")):
        cleaned = cleaned[1:-1].strip()

    return cleaned


def is_meaningless_user_input(text: str) -> bool:
    """Deterministic, lightweight guard to detect random gibberish or uninterpretable user input.

    Returns True ONLY if text is clearly uninterpretable gibberish / random characters.
    Returns False for short but meaningful input like 'I disagree.', 'Yes.', 'No', 'This is risky.'
    """
    if not text:
        return True
    cleaned = text.strip()
    if not cleaned:
        return True

    # Tokenize words (alphanumeric + apostrophe)
    words = [w for w in re.findall(r"[a-zA-Z0-9']+", cleaned)]
    if not words:
        return True

    # Common short English responses that are meaningful
    common_short_phrases = {
        "yes", "no", "agree", "disagree", "maybe", "sure", "true", "false",
        "risky", "good", "bad", "stop", "help", "think", "opinion", "right", "wrong",
        "indeed", "correct", "incorrect", "partially", "valid", "invalid", "why", "how", "what"
    }

    lowered_words = [w.lower() for w in words]
    if any(w in common_short_phrases for w in lowered_words):
        return False

    # Check multi-word inputs: if any word >= 3 chars has 0 vowels, or if vowel ratio < 0.20
    if len(words) >= 2:
        no_vowel_words = [w for w in lowered_words if len(w) >= 3 and not any(c in "aeiouy" for c in w)]
        if no_vowel_words:
            return True
        alpha_chars = [c.lower() for c in cleaned if c.isalpha()]
        if alpha_chars:
            vowels = sum(1 for c in alpha_chars if c in "aeiouy")
            vowel_ratio = vowels / len(alpha_chars)
            if vowel_ratio < 0.20:
                return True

    # Check individual word patterns for random gibberish (e.g. "Kjb...", "12345", "zzzz")
    for w in lowered_words:
        if len(w) >= 3:
            # 3+ letter word with 0 vowels (e.g. "Kjb", "qwr", "zxcv")
            if not any(c in "aeiouy" for c in w):
                return True
            # Repeated identical character 3+ times e.g. "aaaaa"
            if re.search(r"(.)\1{2,}", w):
                return True

    # If text is extremely short (e.g. 1-2 chars) and not a recognized phrase
    if len(cleaned) < 3 and not any(len(w) >= 2 for w in words):
        return True

    return False


def _format_conversation_context(history: Optional[List[Turn]], user_name: Optional[str] = None) -> Tuple[str, str]:
    if not history:
        return "", "RECENT DISCUSSION CONTEXT:\nNo previous turns.\n"
    
    recent_turns = history[-5:]
    context_lines = []
    for t in recent_turns:
        speaker_label = user_name if (t.speaker == "You" and user_name) else t.speaker
        context_lines.append(f"{speaker_label}: \"{t.response or t.claim}\"")
    recent_context_str = "RECENT DISCUSSION CONTEXT:\n" + "\n".join(context_lines) + "\n"
    
    user_turn = next((t for t in reversed(history) if t.speaker == "You" or t.action == "USER_CONTRIBUTION"), None)
    if user_turn:
        user_label = user_name or "You"
        user_text = user_turn.response or user_turn.claim
        if is_meaningless_user_input(user_text):
            user_contrib_str = f"LATEST USER CONTRIBUTION (by {user_label}): \"{user_text}\" [NOTE: Contribution is unclear/gibberish. Do NOT attribute an argument or position to {user_label}. Ask for clarification.]\n"
        else:
            user_contrib_str = f"LATEST USER CONTRIBUTION (by {user_label}): \"{user_text}\"\n"
    else:
        user_contrib_str = ""
        
    return user_contrib_str, recent_context_str

class NeuralArgumentGenerator:
    def __init__(self, analysis: TopicAnalysis, mode: str, router: ModelRouter):
        self.analysis = analysis
        self.mode = mode
        self.router = router

    def build(self, agent: ParticipantAgent, issue: str, action: str, target: Optional[Turn] = None, history: Optional[List[Turn]] = None, user_name: Optional[str] = None) -> Argument:
        p = agent.profile
        a = self.analysis
        direction = "FOR" if agent.position >= 0.08 else "AGAINST" if agent.position <= -0.08 else "NEUTRAL"
        
        # Check if the latest turn was a user contribution that is meaningless/gibberish
        if history:
            last_turn = history[-1]
            if (last_turn.speaker == "You" or last_turn.action == "USER_CONTRIBUTION"):
                user_text = last_turn.response or last_turn.claim
                if is_meaningless_user_input(user_text):
                    user_label = user_name or "You"
                    clarification = f"I'm not sure I caught your point, {user_label}. Could you clarify your position on this?"
                    return Argument(clarification, f"Clarification requested for gibberish input from {user_label}", "", "", 0.5, direction, issue)

        # Base structured argument (used as fallback or reasoning context)
        if direction == "FOR":
            claim = f"A carefully designed approach should proceed because it can improve {issue}."
        elif direction == "AGAINST":
            claim = f"The proposal should not advance without credible safeguards for {issue}."
        else:
            claim = f"The decision should be conditional on evidence about {issue}."
            
        evidence = next(
            (e for e in a.evidence_requirements if any(w in e for w in issue.split())),
            a.evidence_requirements[0]
        )
        
        argument = Argument(claim, "", evidence, a.assumptions[0], round(0.55 + 0.35 * p.confidence, 2), direction, issue)
        
        # Neural generation
        target_claim = target.argument.claim if target else None
        target_str = f"TARGET ARGUMENT: {target_claim}" if target_claim else "TARGET ARGUMENT: none; introduce a new relevant point."
        
        user_contrib_str, recent_context_str = _format_conversation_context(history, user_name)
        
        user_name_instruction = ""
        if user_name and user_name.strip():
            clean_name = user_name.strip()
            user_name_instruction = (
                f"HUMAN PARTICIPANT NAME: {clean_name}\n"
                f"INSTRUCTION: When referring to the human participant or their contribution, refer to them naturally by their actual name '{clean_name}'. "
                f"NEVER refer to them as 'the human', 'human', 'the user', 'user', 'USER_CONTRIBUTION', or 'the participant'. "
                f"Do not repeat their name unnaturally in every sentence—only use it when referencing their points.\n"
            )
        
        if self.mode == "consensus" and action == "SYNTHESIZE":
            task_prompt = (
                "TASK: Synthesize the discussion toward consensus. Identify areas of agreement, reconcile compatible viewpoints, "
                "acknowledge remaining disagreements, propose a balanced common position while respecting your persona's expertise, "
                "and respond directly to the recent discussion context."
            )
        elif self.mode == "balanced":
            task_prompt = (
                "TASK: Write a concise substantive group-discussion response. Preserve independent critical viewpoints, encourage "
                "constructive disagreement or counterarguments where justified, and avoid artificially forcing agreement. "
                "Respond directly to recent context and target if given."
            )
        else:
            task_prompt = (
                "TASK: Write a concise substantive group-discussion response. Address the recent discussion context and target if given. "
                "Respond directly to the actual user contribution if one was made."
            )

        system_prompt = (
            "You participate in a research-only group discussion. Respond directly to context; do not reveal private reasoning. "
            "Do not include speaker name headers or markdown preambles like '**Name:**'. "
            "Keep responses concise and natural: 50–65 words normally (acceptable range: 45–75 words, strictly under 85 words max). "
            "Structure: ONE clear argument + ONE useful supporting point + optional short counterpoint/question. "
            "Avoid lengthy introductions, topic repetition, generic filler, unnecessary examples, explaining obvious points, or essay conclusions. "
            "GROUNDING REQUIREMENT: The latest human contribution is raw user text. Never infer a meaning that is not explicitly present in that text. "
            "If the contribution is unclear, gibberish, or lacks a discernible position, do not fabricate one. Ask the participant to clarify instead."
        )
        length_guidelines = (
            "RESPONSE STYLE & LENGTH:\n"
            "- Target length: 50–65 words (acceptable range: 45–75 words, hard max: 85 words).\n"
            "- Structure: ONE clear argument + ONE useful supporting point + optional short counterpoint/question.\n"
            "- Speak naturally like a real participant in a spoken Group Discussion.\n"
            "- Avoid repeating the topic, lengthy intros, generic filler, excessive examples, or formal essay conclusions.\n"
            "- Never infer or fabricate a position from unclear or gibberish user contributions.\n"
        )
        user_prompt = (
            f"TOPIC: {a.topic}\n"
            f"PARTICIPANT: {p.name}, {p.role}\n"
            f"PERSONALITY: {', '.join(p.traits)}; {p.communication_style}\n"
            f"STANCE: {agent.position:+.2f}\n"
            f"{user_name_instruction}"
            f"{user_contrib_str}"
            f"{recent_context_str}"
            f"{target_str}\n"
            f"{task_prompt}\n"
            f"{length_guidelines}"
        )
        
        result = self.router.generate(
            task="gd_generation",
            system_prompt=system_prompt,
            user_prompt=user_prompt
        )
        generated = _clean_response_text(result.text, p.name)
        
        if generated:
            argument.claim = generated
            argument.reasoning = f"Generated by model; structured issue: {issue}."
            
        return argument

class NeuralCounterArgumentGenerator:
    def __init__(self, analysis: TopicAnalysis, router: ModelRouter, mode: str = "balanced"):
        self.analysis = analysis
        self.router = router
        self.mode = mode

    def build(self, agent: ParticipantAgent, target_turn: Turn, history: Optional[List[Turn]] = None, user_name: Optional[str] = None) -> Argument:
        p = agent.profile
        target = target_turn.argument if target_turn else None
        
        raw_issue = target.issue if (target and target.issue) else "discussion"
        issue = str(raw_issue) if raw_issue is not None else "discussion"
        
        # Check if the latest turn was a user contribution that is meaningless/gibberish
        if history:
            last_turn = history[-1]
            if (last_turn.speaker == "You" or last_turn.action == "USER_CONTRIBUTION"):
                user_text = last_turn.response or last_turn.claim
                if is_meaningless_user_input(user_text):
                    user_label = user_name or "You"
                    clarification = f"I'm not sure I caught your point, {user_label}. Could you clarify your position on this?"
                    return Argument(clarification, f"Clarification requested for gibberish input from {user_label}", "", "", 0.5, "NEUTRAL", issue)

        counterclaim = f"{issue.title()} deserves a narrower, testable safeguard before that conclusion is accepted."
        
        evidence = target.evidence_needed if (target and target.evidence_needed) else ""
        target_pos = target.position if (target and target.position) else "NEUTRAL"
        pos_dir = "AGAINST" if target_pos == "FOR" else "FOR"
        
        argument = Argument(
            counterclaim,
            "",
            evidence,
            "the target's expected outcome generalizes",
            round(0.58 + 0.30 * p.confidence, 2),
            pos_dir,
            issue,
        )
        
        # Neural generation
        target_claim = ""
        if target and target.claim:
            target_claim = target.claim
        elif target_turn and target_turn.claim:
            target_claim = target.claim
            
        target_str = f"TARGET ARGUMENT: {target_claim}" if target_claim else "TARGET ARGUMENT: none; introduce a new relevant point."
        
        user_contrib_str, recent_context_str = _format_conversation_context(history, user_name)
        
        user_name_instruction = ""
        if user_name and user_name.strip():
            clean_name = user_name.strip()
            user_name_instruction = (
                f"HUMAN PARTICIPANT NAME: {clean_name}\n"
                f"INSTRUCTION: When referring to the human participant or their contribution, refer to them naturally by their actual name '{clean_name}'. "
                f"NEVER refer to them as 'the human', 'human', 'the user', 'user', 'USER_CONTRIBUTION', or 'the participant'. "
                f"Do not repeat their name unnaturally in every sentence—use it naturally only when referencing their points.\n"
            )
        
        if self.mode == "consensus":
            task_prompt = (
                "TASK: Write a constructive counterargument. Focus on clarifying boundaries and safeguards to build consensus. "
                "Address recent context and target directly."
            )
        else:
            task_prompt = (
                "TASK: Write a concise substantive counterargument. Preserve independent critical viewpoints, address recent context, "
                "and directly challenge the target argument."
            )

        system_prompt = (
            "You participate in a research-only group discussion. Respond directly to context; do not reveal private reasoning. "
            "Do not include speaker name headers or markdown preambles like '**Name:**'. "
            "Keep responses concise and natural: 50–65 words normally (acceptable range: 45–75 words, strictly under 85 words max). "
            "Structure: ONE clear argument + ONE useful supporting point + optional short counterpoint/question. "
            "Avoid lengthy introductions, topic repetition, generic filler, unnecessary examples, explaining obvious points, or essay conclusions. "
            "GROUNDING REQUIREMENT: The latest human contribution is raw user text. Never infer a meaning that is not explicitly present in that text. "
            "If the contribution is unclear, gibberish, or lacks a discernible position, do not fabricate one. Ask the participant to clarify instead."
        )
        length_guidelines = (
            "RESPONSE STYLE & LENGTH:\n"
            "- Target length: 50–65 words (acceptable range: 45–75 words, hard max: 85 words).\n"
            "- Structure: ONE clear argument + ONE useful supporting point + optional short counterpoint/question.\n"
            "- Speak naturally like a real participant in a spoken Group Discussion.\n"
            "- Avoid repeating the topic, lengthy intros, generic filler, excessive examples, or formal essay conclusions.\n"
            "- Never infer or fabricate a position from unclear or gibberish user contributions.\n"
        )
        user_prompt = (
            f"TOPIC: {self.analysis.topic}\n"
            f"PARTICIPANT: {p.name}, {p.role}\n"
            f"PERSONALITY: {', '.join(p.traits)}; {p.communication_style}\n"
            f"STANCE: {agent.position:+.2f}\n"
            f"{user_name_instruction}"
            f"{user_contrib_str}"
            f"{recent_context_str}"
            f"{target_str}\n"
            f"{task_prompt}\n"
            f"{length_guidelines}"
        )
        
        result = self.router.generate(
            task="gd_generation",
            system_prompt=system_prompt,
            user_prompt=user_prompt
        )
        generated = _clean_response_text(result.text, p.name)
        
        if generated:
            argument.claim = generated
            argument.reasoning = f"Fine-tuned targeted response to {target_turn.speaker}."
            
        return argument

class DiscussionManager:
    def __init__(self, topic: str, profiles: List[PersonalityProfile], config: Dict[str, Any], router: ModelRouter):
        self.topic = topic
        self.analysis = TopicAnalyzer().analyze(topic)
        self.config = config
        self.mode = config.get("mode", "balanced")
        self.agents = [ParticipantAgent(p, config.get("similarity_threshold", 0.8)) for p in profiles]
        self.generator = NeuralArgumentGenerator(self.analysis, self.mode, router)
        self.counter = NeuralCounterArgumentGenerator(self.analysis, router, mode=self.mode)
        self.history: List[Turn] = []
        self.unresolved = []
        self.new_claims = []
        self.round_no = 1
        self.turn_index = 0

    def calculate_consensus_score(self) -> float:
        positions = [a.position for a in self.agents]
        if not positions:
            return 50.0
        spread = float(np.max(positions) - np.min(positions)) if len(positions) > 1 else 0.0
        raw = 100.0 * (1.0 - (spread / 2.0))
        return round(float(np.clip(raw, 0.0, 100.0)), 1)

    def _issue(self, agent: ParticipantAgent, turn_index: int) -> str:
        pool = self.analysis.benefits + self.analysis.risks + self.analysis.controversial_points
        if not pool:
            pool = ["discussion"]
        unused = [x for x in pool if x not in [a.issue for a in agent.arguments if getattr(a, "issue", None)]]
        effective_pool = unused or pool
        if not effective_pool:
            effective_pool = ["discussion"]
        return effective_pool[turn_index % len(effective_pool)]

    def _render(self, agent: ParticipantAgent, action: str, argument: Argument, target: Optional[Turn]) -> str:
        # Since we use LLM, the claim *is* the response.
        return _clean_response_text(argument.claim, agent.profile.name)

    def step(self) -> Optional[Turn]:
        """Executes a single turn and returns it. Returns None if the discussion is finished."""
        rounds = self.config.get("num_rounds", 4)
        if self.round_no > rounds:
            return None
            
        agent = self.agents[self.turn_index % len(self.agents)]
        user_name = self.config.get("user_name")
        
        action, target = agent.decide(self.history, self.analysis, self.round_no, self.mode)
        issue = self._issue(agent, (self.round_no - 1) * len(self.agents) + self.turn_index)
        
        if action == "COUNTERARGUE" and target and target.argument:
            arg = self.counter.build(agent, target, history=self.history, user_name=user_name)
        else:
            arg = self.generator.build(agent, issue, action, target, history=self.history, user_name=user_name)
            
        if not agent.memory.is_novel(arg.claim):
            issue = self._issue(agent, self.turn_index + self.round_no + 1)
            arg = self.generator.build(agent, issue, "INTRODUCE_ARGUMENT", history=self.history, user_name=user_name)
            action = "INTRODUCE_ARGUMENT"
            target = None
            
        arg.speaker = agent.profile.name
        arg.round = self.round_no
        response = self._render(agent, action, arg, target)
        
        target_turn_index = None
        if target:
            try:
                target_turn_index = self.history.index(target)
            except ValueError:
                pass

        turn = Turn(
            speaker=agent.profile.name,
            round=self.round_no,
            action=action,
            target=target.speaker if target else None,
            position=round(agent.position, 2),
            claim=arg.claim,
            response=response,
            confidence=agent.confidence,
            argument=arg,
            counter_target=target.argument.claim if (target and target.argument) else None,
            target_turn_index=target_turn_index
        )
        
        self.history.append(turn)
        agent.arguments.append(arg)
        agent.memory.add(arg.claim)
        
        if target:
            agent.targets.append(target.speaker)
            agent.interactions.append((target.speaker, action))
            
        agent.update_position(target, arg)
        
        # Apply modest consensus shift toward group mean position during synthesis in consensus mode
        if self.mode == "consensus" and action == "SYNTHESIZE":
            mean_pos = float(np.mean([a.position for a in self.agents]))
            agent.position = float(np.clip(agent.position + 0.15 * (mean_pos - agent.position), -1.0, 1.0))
            if agent.position_history:
                agent.position_history[-1] = round(agent.position, 2)

        if action == "COUNTERARGUE" and target:
            self.unresolved.append((agent.profile.name, target.speaker, arg.issue if (arg and arg.issue) else "discussion"))
            
        self.new_claims.append(arg.claim)
        
        self.turn_index += 1
        if self.turn_index % len(self.agents) == 0:
            self.round_no += 1
            
        return turn

    def records(self):
        return [
            {
                "speaker": t.speaker,
                "round": t.round,
                "action": t.action,
                "target": t.target,
                "position": t.position,
                "claim": t.claim,
                "response": t.response,
                "confidence": t.confidence,
                "issue": t.argument.issue if t.argument else "discussion",
                "argument_position": t.argument.position if t.argument else "NEUTRAL",
            }
            for t in self.history
        ]

    @classmethod
    def from_history(
        cls,
        history: List[Dict[str, Any]],
        topic: str,
        config: Dict[str, Any],
        router: ModelRouter
    ) -> DiscussionManager:
        # Helper conversions to prevent null/None parsing type crashes
        def _sf(val, default: float = 0.0) -> float:
            if val is None:
                return default
            try:
                return float(val)
            except (ValueError, TypeError):
                return default

        def _si(val, default: int = 1) -> int:
            if val is None:
                return default
            try:
                return int(val)
            except (ValueError, TypeError):
                return default

        def _ss(val, default: str = "") -> str:
            return str(val) if val is not None else default

        # Re-initialize manager using class constructor
        manager = cls(topic=topic, profiles=default_profiles(), config=config, router=router)
        
        # Sort history by turn_index to ensure chronological order
        sorted_history = sorted(history, key=lambda x: _si(x.get("turn_index"), 0))
        
        for row in sorted_history:
            content_field = _ss(row.get("content"), "")
            
            # Reconstruct the Turn and Argument structures from the JSON envelope
            try:
                data = json.loads(content_field) if content_field else {}
            except Exception:
                # Fallback: parse as plain text if it's not valid JSON
                data = {
                    "claim": content_field,
                    "response": content_field,
                    "speaker": _ss(row.get("speaker")),
                    "round": _si(row.get("round"), 1),
                    "action": _ss(row.get("action"), "INTRODUCE_ARGUMENT"),
                    "target": row.get("target"),
                    "position": _sf(row.get("position"), 0.0),
                    "confidence": _sf(row.get("confidence"), 0.5),
                    "issue": _ss(row.get("issue"), "discussion"),
                    "argument": {
                        "claim": content_field,
                        "reasoning": "Fallback from text content",
                        "evidence_needed": "",
                        "assumptions": "",
                        "strength": 0.5,
                        "position": "NEUTRAL",
                        "issue": _ss(row.get("issue"), "discussion")
                    },
                    "counter_target": row.get("counter_target")
                }
            
            # Find the ParticipantAgent corresponding to the speaker name
            speaker_name = _ss(data.get("speaker")) or _ss(row.get("speaker"))
            is_user = (speaker_name == "You" or row.get("speaker_type") == "user" or data.get("action") == "USER_CONTRIBUTION")
            
            agent = next((a for a in manager.agents if a.profile.name == speaker_name), None)
            if not agent and not is_user:
                continue
                
            # Reconstruct nested Argument object
            arg_data = data.get("argument") if isinstance(data.get("argument"), dict) else {}
            arg_claim = _ss(arg_data.get("claim")) or _ss(data.get("claim"))
            arg = Argument(
                claim=arg_claim,
                reasoning=_ss(arg_data.get("reasoning"), "User contribution" if is_user else ""),
                evidence_needed=_ss(arg_data.get("evidence_needed")),
                assumptions=_ss(arg_data.get("assumptions")),
                strength=_sf(arg_data.get("strength"), 0.8 if is_user else 0.5),
                position=_ss(arg_data.get("position"), "NEUTRAL"),
                issue=_ss(arg_data.get("issue"), "discussion"),
                speaker=speaker_name,
                round=_si(data.get("round"), 1)
            )
            
            # Reconstruct the target Turn object using target_turn_index
            target_name = data.get("target")
            target_turn = None
            target_turn_index = data.get("target_turn_index")
            if target_turn_index is not None:
                idx = _si(target_turn_index, -1)
                if 0 <= idx < len(manager.history):
                    target_turn = manager.history[idx]
            if target_turn is None and target_name:
                # Fallback for backward compatibility
                target_turn = next((t for t in reversed(manager.history) if t.speaker == target_name), None)

            # Reconstruct Turn object
            turn = Turn(
                speaker=speaker_name,
                round=_si(data.get("round"), 1),
                action=_ss(data.get("action"), "USER_CONTRIBUTION" if is_user else "INTRODUCE_ARGUMENT"),
                target=target_name,
                position=_sf(data.get("position"), 0.0 if is_user else (agent.position if agent else 0.0)),
                claim=_ss(data.get("claim")),
                response=_ss(data.get("response")),
                confidence=_sf(data.get("confidence"), 1.0 if is_user else (agent.confidence if agent else 0.5)),
                argument=arg,
                counter_target=data.get("counter_target"),
                target_turn_index=target_turn_index
            )
            
            # Update manager states
            manager.history.append(turn)
            manager.new_claims.append(arg.claim)
            
            if agent:
                agent.arguments.append(arg)
                agent.memory.add(arg.claim)
                
                # Update agent interaction history
                if target_name:
                    agent.targets.append(target_name)
                    agent.interactions.append((target_name, turn.action))
                    
                # Update stance position using resolved target_turn
                agent.update_position(target_turn, arg)
                
                if turn.action == "COUNTERARGUE" and target_name:
                    manager.unresolved.append((speaker_name, target_name, arg.issue if (arg and arg.issue) else "discussion"))
                    
            # Increment turn_index and round_no for AI participant turns
            if not is_user:
                manager.turn_index += 1
                if manager.turn_index % len(manager.agents) == 0:
                    manager.round_no += 1
                
        return manager

    def pop_last_turn(self) -> Turn | None:
        if not self.history:
            return None
        last_turn = self.history.pop()
        claim = getattr(last_turn, "claim", "")
        if self.new_claims and self.new_claims[-1] == claim:
            self.new_claims.pop()
            
        is_user = (last_turn.speaker == "You" or last_turn.action == "USER_CONTRIBUTION")
        if not is_user:
            if self.turn_index % len(self.agents) == 0 and self.round_no > 1:
                self.round_no -= 1
            self.turn_index = max(0, self.turn_index - 1)
            
        agent = next((a for a in self.agents if a.profile.name == last_turn.speaker), None)
        if agent:
            if agent.arguments and getattr(agent.arguments[-1], "claim", "") == claim:
                agent.arguments.pop()
            if agent.memory.claims and agent.memory.claims[-1] == claim:
                agent.memory.claims.pop()
            elif claim in agent.memory.claims:
                agent.memory.claims.remove(claim)
            if last_turn.target and agent.targets and agent.targets[-1] == last_turn.target:
                agent.targets.pop()
            if last_turn.target and agent.interactions and agent.interactions[-1] == (last_turn.target, last_turn.action):
                agent.interactions.pop()
            if len(agent.position_history) > 1:
                agent.position_history.pop()
                agent.position = agent.position_history[-1]
                
        if last_turn.action == "COUNTERARGUE" and last_turn.target and self.unresolved:
            if self.unresolved[-1][:2] == (last_turn.speaker, last_turn.target):
                self.unresolved.pop()
                
        return last_turn


class DiscussionEvaluator:
    def evaluate(self, manager: DiscussionManager):
        rows = manager.records()
        claims = [r["claim"] for r in rows]
        
        if len(claims) > 1:
            try:
                X = TfidfVectorizer(stop_words="english").fit_transform(claims)
                S = cosine_similarity(X)
                triu_indices = np.triu_indices_from(S, 1)
                similarity_threshold = manager.config.get("similarity_threshold", 0.8)
                repetition = float(np.mean(S[triu_indices] >= similarity_threshold))
                diversity = float(1 - np.mean(S[triu_indices]))
            except ValueError:
                repetition, diversity = 0, 1
        else:
            repetition, diversity = 0, 1
            
        topic_words = set(re.findall(r"[a-z]{4,}", manager.analysis.topic.lower()))
        relevance = np.mean([bool(topic_words & set(re.findall(r"[a-z]{4,}", (r["claim"] + r["response"]).lower()))) for r in rows]) if rows else 0
        
        counters = [r for r in rows if r["action"] == "COUNTERARGUE"]
        counter_rel = np.mean([1.0 if r["target"] else 0.0 for r in counters]) if counters else 0.5
        
        profile_words = {a.profile.name: set(" ".join(a.profile.values + [a.profile.expertise]).lower().split()) for a in manager.agents}
        personality = np.mean([bool(profile_words.get(r["speaker"], set()) & set(r["response"].lower().split())) for r in rows]) if rows else 0

        
        ai_rows = [r for r in rows if r["speaker"] != "You"]
        counts = Counter(r["speaker"] for r in (ai_rows or rows))
        engagement = min(counts.values()) / max(counts.values()) if counts else 0
        
        changes = [abs(a.position_history[-1] - a.position_history[0]) for a in manager.agents]
        stability = 1 - float(np.mean([max(0, c - 0.35) / 0.65 for c in changes]))
        
        coherence = np.mean([1.0 if r["action"] != "COUNTERARGUE" or r["target"] else 0.0 for r in rows]) if rows else 0
        
        quality = 100 * np.mean([diversity, relevance, counter_rel, personality, coherence])
        
        return {
            "diversity": round(100 * diversity, 1),
            "repetition": round(100 * repetition, 1),
            "counterargument_relevance": round(100 * counter_rel, 1),
            "topic_relevance": round(100 * relevance, 1),
            "personality_consistency": round(100 * personality, 1),
            "participant_engagement": round(100 * engagement, 1),
            "position_stability": round(100 * stability, 1),
            "mean_position_change": round(float(np.mean(changes)), 3),
            "coherence": round(100 * coherence, 1),
            "quality_score": round(quality, 1),
        }

    def summary(self, manager: DiscussionManager):
        finals = {a.profile.name: round(a.position, 2) for a in manager.agents}
        agreement = [
            a.issue
            for agent in manager.agents
            for a in agent.arguments
            if a.position == "NEUTRAL"
        ]
        
        score = manager.calculate_consensus_score()
        mean_pos = float(np.mean([a.position for a in manager.agents])) if manager.agents else 0.0
        
        if score >= 75.0:
            if mean_pos > 0.1:
                final_consensus = f"High consensus ({score:.1f}/100): Participants align on supportive deployment with common safeguards."
            elif mean_pos < -0.1:
                final_consensus = f"High consensus ({score:.1f}/100): Participants align on precautionary restrictions and risk mitigations."
            else:
                final_consensus = f"High consensus ({score:.1f}/100): Participants reach a balanced common framework."
        elif score >= 45.0:
            final_consensus = f"Moderate consensus ({score:.1f}/100): Common ground established on key safeguards, while distinct risk priorities remain."
        else:
            final_consensus = f"Low consensus ({score:.1f}/100): Substantial divergence remains across participant risk and innovation stances."

        return {
            "topic_summary": manager.analysis.central_question,
            "participant_positions": finals,
            "strongest_arguments": [a.claim for ag in manager.agents for a in sorted(ag.arguments, key=lambda x: x.strength, reverse=True)[:1]],
            "strongest_counterarguments": [t.response for t in manager.history if t.action == "COUNTERARGUE"][:4],
            "points_of_agreement": list(dict.fromkeys(agreement)) or ["Need for evidence and safeguards"],
            "points_of_disagreement": list(dict.fromkeys(x[2] for x in manager.unresolved))[:6],
            "unresolved_questions": manager.analysis.controversial_points,
            "final_consensus": final_consensus,
            "consensus_score": score,
        }

