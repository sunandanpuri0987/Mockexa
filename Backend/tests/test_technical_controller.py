import pytest

from app.controllers.technical_controller import (
    CURATED_QUESTION_BANK,
    CandidateProfile,
    CuratedTechnicalBackend,
    InterviewController,
    InterviewMode,
)


def make_controller():
    return InterviewController(CURATED_QUESTION_BANK, CuratedTechnicalBackend(), learning_rate=0.3, domain_balance=True)


def test_start_returns_first_question_in_selected_domain():
    controller = make_controller()
    profile = CandidateProfile(
        name="Test Candidate", target_role="SWE Intern", experience="Intermediate",
        selected_domains=("Algorithms",), desired_difficulty=3,
    )
    q = controller.start(profile, InterviewMode.PRACTICE, max_questions=5)
    assert q.domain == "Algorithms"
    assert controller.state.status.name == "ACTIVE"


def test_start_rejects_domain_with_no_questions():
    controller = make_controller()
    profile = CandidateProfile(
        name="Test", target_role="SWE", experience="Beginner",
        selected_domains=("Quantum Computing",),
    )
    with pytest.raises(ValueError):
        controller.start(profile)


def test_full_interview_completes_and_reports():
    controller = make_controller()
    profile = CandidateProfile(
        name="Anwesha", target_role="Software Engineering Intern", experience="Intermediate",
        selected_domains=("Algorithms", "Data Structures", "Operating Systems", "Coding", "DBMS"),
        desired_difficulty=3,
    )
    controller.start(profile, InterviewMode.LEARNING, max_questions=5)
    good_answer = "This is correct because the sorted input allows binary search to halve the search space, giving logarithmic complexity."
    for _ in range(5):
        if controller.state.status.name == "COMPLETED":
            break
        controller.submit_answer(good_answer)
    report = controller.report()
    assert report["questions_answered"] >= 1
    assert 0 <= report["overall_score"] <= 100
    assert report["performance_band"] in {
        "Exceptional", "Strong", "Good", "Developing", "Needs Improvement", "Foundational Gaps",
    }


def test_empty_answer_is_insufficient_evidence():
    controller = make_controller()
    profile = CandidateProfile(
        name="Test", target_role="SWE", experience="Beginner", selected_domains=("Algorithms",),
    )
    controller.start(profile, InterviewMode.PRACTICE, max_questions=3)
    analysis, decision, next_q = controller.submit_answer("")
    assert analysis.classification == "INSUFFICIENT_EVIDENCE"


def test_submit_answer_after_completion_raises():
    controller = make_controller()
    profile = CandidateProfile(
        name="Test", target_role="SWE", experience="Beginner", selected_domains=("Algorithms",),
    )
    controller.start(profile, InterviewMode.PRACTICE, max_questions=1)
    controller.submit_answer("a reasonable answer")
    assert controller.state.status.name == "COMPLETED"
    with pytest.raises(RuntimeError):
        controller.submit_answer("another answer")


def test_networks_removed_and_coding_domain_available():
    # Networks is rejected as an invalid domain with no questions
    controller = make_controller()
    profile_net = CandidateProfile(name="Test", target_role="SWE", experience="Beginner", selected_domains=("Networks",))
    with pytest.raises(ValueError):
        controller.start(profile_net)
        
    profile_comp_net = CandidateProfile(name="Test", target_role="SWE", experience="Beginner", selected_domains=("Computer Networks",))
    with pytest.raises(ValueError):
        controller.start(profile_comp_net)

    # Coding domain starts successfully
    profile_coding = CandidateProfile(name="Test", target_role="SWE", experience="Intermediate", selected_domains=("Coding",), desired_difficulty=3)
    q = controller.start(profile_coding, InterviewMode.PRACTICE, max_questions=3)
    assert q.domain == "Coding"
    assert "PROBLEM:" in q.question
    assert "CONSTRAINTS:" in q.question


def test_coding_submission_difficulty_and_static_evaluation():
    controller = make_controller()
    profile = CandidateProfile(name="Coder", target_role="Backend Developer", experience="Intermediate", selected_domains=("Coding",), desired_difficulty=2)
    q1 = controller.start(profile, InterviewMode.PRACTICE, max_questions=3)
    assert q1.domain == "Coding"
    assert q1.difficulty == 2  # Palindrome problem

    code_answer = """
    # Approach: string manipulation and two pointers technique
    def is_palindrome(s: str) -> bool:
        filtered = [c.lower() for c in s if c.isalnum()]
        left, right = 0, len(filtered) - 1
        while left < right:
            if filtered[left] != filtered[right]:
                return False
            left += 1
            right -= 1
        return True
    # Time complexity: O(N), Space complexity: O(N)
    """

    analysis, decision, next_q = controller.submit_answer(code_answer)
    assert analysis.classification in {"CORRECT", "MOSTLY_CORRECT"}

    report = controller.report()
    assert report["questions_answered"] >= 1
    log_entry = report["question_log"][0]
    assert "code_evaluation" in log_entry
    code_eval = log_entry["code_evaluation"]
    assert code_eval["evaluation_type"] == "static_code_reasoning"
    assert isinstance(code_eval["score"], int)
    assert "time_complexity" in code_eval
def test_same_session_never_repeats_questions():
    # A. Same session never repeats a question
    controller = make_controller()
    profile = CandidateProfile(name="Test", target_role="SWE", experience="Intermediate", selected_domains=("Data Structures",), desired_difficulty=3)
    controller.start(profile, InterviewMode.PRACTICE, max_questions=3)
    
    for _ in range(3):
        if controller.state.status.name == "COMPLETED":
            break
        controller.submit_answer("A valid response with indexed access and memory trade-offs.")
        
    asked_ids = [q.id for q in controller.state.question_history]
    assert len(asked_ids) == len(set(asked_ids)), "Session contained duplicate questions!"


def test_session_question_randomization():
    # B. Starting multiple sessions does not always return the exact same first question
    first_q_ids = set()
    profile = CandidateProfile(name="Test", target_role="SWE", experience="Intermediate", selected_domains=("Data Structures",), desired_difficulty=3)
    
    for _ in range(20):
        c = make_controller()
        q = c.start(profile, InterviewMode.PRACTICE, max_questions=1)
        first_q_ids.add(q.id)
        
    # Data Structures has 3 questions at difficulty 3 (ds-array-list, ds-hash, ds-tree).
    # Over 20 starts, randomization must pick at least 2 distinct starting questions.
    assert len(first_q_ids) > 1, f"Expected randomized starting questions, but got only: {first_q_ids}"


def test_difficulty_adaptation_preserved():
    # C. Difficulty adaptation is preserved
    controller_easy = make_controller()
    profile_easy = CandidateProfile(name="Test", target_role="SWE", experience="Beginner", selected_domains=("Algorithms",), desired_difficulty=2)
    q_easy = controller_easy.start(profile_easy, InterviewMode.PRACTICE, max_questions=1)
    assert q_easy.difficulty == 2

    controller_hard = make_controller()
    profile_hard = CandidateProfile(name="Test", target_role="SWE", experience="Advanced", selected_domains=("Algorithms",), desired_difficulty=4)
    q_hard = controller_hard.start(profile_hard, InterviewMode.PRACTICE, max_questions=1)
    assert q_hard.difficulty == 4


def test_domain_balancing_preserved():
    # D. Existing domain balancing still works
    controller = make_controller()
    profile = CandidateProfile(name="Test", target_role="SWE", experience="Intermediate", selected_domains=("Algorithms", "DBMS"), desired_difficulty=3)
    controller.start(profile, InterviewMode.PRACTICE, max_questions=4)
    
    for _ in range(3):
        if controller.state.status.name == "COMPLETED":
            break
        controller.submit_answer("Balanced response containing index lookup and binary search.")
        
    domains_asked = [q.domain for q in controller.state.question_history]
    assert "Algorithms" in domains_asked
    assert "DBMS" in domains_asked


def test_new_session_starts_with_fresh_question_state():
    controller1 = make_controller()
    profile1 = CandidateProfile(name="Test1", target_role="SWE", experience="Intermediate", selected_domains=("Data Structures",), desired_difficulty=3)
    controller1.start(profile1, InterviewMode.PRACTICE, max_questions=3)
    controller1.submit_answer("A valid answer discussing array and linked list access.")
    assert len(controller1.state.question_history) == 1

    # Fresh controller instance
    controller2 = make_controller()
    profile2 = CandidateProfile(name="Test2", target_role="SWE", experience="Intermediate", selected_domains=("Data Structures",), desired_difficulty=3)
    controller2.start(profile2, InterviewMode.PRACTICE, max_questions=3)

    # controller2 must start with empty question_history
    assert controller2.state.question_history == []
    assert controller2.state.answer_history == []
    assert controller2.state.analyses == []


def test_randomized_candidate_selection_mechanism(monkeypatch):
    import random
    recorded_choices = []

    def mock_random_choice(seq):
        recorded_choices.append(list(seq))
        return seq[0]

    monkeypatch.setattr(random, "choice", mock_random_choice)

    c = make_controller()
    profile = CandidateProfile(name="Test", target_role="SWE", experience="Intermediate", selected_domains=("Data Structures",), desired_difficulty=3)
    c.start(profile, InterviewMode.PRACTICE, max_questions=1)

    assert len(recorded_choices) == 1
    candidate_ids = {q.id for q in recorded_choices[0]}
    assert "ds-array-list" in candidate_ids
    assert "ds-hash" in candidate_ids
    assert "ds-tree" in candidate_ids




