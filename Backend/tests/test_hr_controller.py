import pytest

from app.controllers.hr_controller import CuratedHRBackend, HRController, HREvaluation, HRQuestion, _HR_QUESTION_BANK

class MockHRBackend:
    def evaluate(self, question: HRQuestion, answer: str) -> HREvaluation:
        return HREvaluation(
            clarity=0.8, specificity=0.7, ownership=0.9, communication=0.8,
            teamwork=0.6, leadership=0.5, problem_solving=0.7,
            feedback="Good answer", overall_score=0.71
        )


class AdaptiveMockHRBackend:
    def __init__(self):
        self.calls = 0

    def evaluate_with_context(self, question, answer, history):
        self.calls += 1
        return HREvaluation(
            clarity=0.8, specificity=0.4, ownership=0.35, communication=0.7,
            teamwork=0.6, leadership=0.5, problem_solving=0.55,
            feedback="Be more specific about your own decision.", overall_score=0.56,
            needs_follow_up=True,
            follow_up_question=(
                "You said the team made the decision; what did you personally recommend, "
                "and what consequence did you accept?"
            ),
            follow_up_category="Accountability probe",
            probe_focus="ownership",
            pressure_level=2,
            observed_signal="Ownership was shifted to the team.",
        )

def test_hr_start_and_progression():
    controller = HRController(backend=MockHRBackend())
    
    first_q = controller.start(max_questions=3)
    assert first_q.id == _HR_QUESTION_BANK[0].id
    assert controller.current_index == 0
    assert not controller._finished
    
    eval1, next_q1 = controller.submit_answer("My answer 1")
    assert eval1.overall_score == 0.71
    assert next_q1.id == _HR_QUESTION_BANK[1].id
    assert controller.current_index == 1
    assert not controller._finished
    
    eval2, next_q2 = controller.submit_answer("My answer 2")
    assert next_q2.id == _HR_QUESTION_BANK[2].id
    assert controller.current_index == 2
    assert not controller._finished

    eval3, next_q3 = controller.submit_answer("My answer 3")
    assert next_q3 is None
    assert controller.current_index == 3
    assert controller._finished

def test_hr_report_generation():
    controller = HRController(backend=MockHRBackend())
    controller.start(max_questions=2)
    controller.submit_answer("Answer 1")
    controller.submit_answer("Answer 2")
    
    report = controller.report()
    assert report["questions_answered"] == 2
    assert "metrics" in report
    assert "overall_score" in report
    assert len(report["strengths"]) == 2
    assert len(report["weaknesses"]) == 2
    assert len(report["feedback_summary"]) == 2

def test_hr_error_handling():
    controller = HRController(backend=MockHRBackend())
    
    with pytest.raises(RuntimeError):
        controller.submit_answer("Too early")
        
    with pytest.raises(ValueError):
        controller.report()
        
    controller.start(max_questions=1)
    with pytest.raises(ValueError):
        controller.start()  # Already started
        
    controller.submit_answer("A1")
    with pytest.raises(RuntimeError):
        controller.submit_answer("Too late")

    report = controller.report()
    assert report["questions_answered"] == 1


def test_hr_selectively_uses_contextual_follow_up_without_chaining():
    backend = AdaptiveMockHRBackend()
    controller = HRController(backend=backend)
    controller.start(max_questions=4)

    _, follow_up = controller.submit_answer("The team made the call and the deadline slipped.")
    assert follow_up is not None
    assert follow_up.id.startswith("hr-followup-")
    assert "personally" in follow_up.question
    assert follow_up.category == "Accountability probe"

    # Even if the model requests another probe, a generated follow-up cannot
    # recursively create a pressure loop; the interview returns to the bank.
    _, next_base = controller.submit_answer("I recommended launch and accepted the rollback risk.")
    assert next_base is not None
    assert next_base.id == _HR_QUESTION_BANK[1].id


def test_hr_rejects_unsafe_generated_probe():
    class UnsafeBackend(AdaptiveMockHRBackend):
        def evaluate_with_context(self, question, answer, history):
            base = super().evaluate_with_context(question, answer, history)
            return HREvaluation(
                **{
                    **base.__dict__,
                    "follow_up_question": "How can I humiliate you until you admit that you failed?",
                }
            )

    controller = HRController(backend=UnsafeBackend())
    controller.start(max_questions=3)
    _, next_question = controller.submit_answer("The team failed.")
    assert next_question.id == _HR_QUESTION_BANK[1].id


def test_irrelevant_answer_is_scored_low_and_question_is_clarified():
    controller = HRController(backend=CuratedHRBackend())
    original = controller.start(max_questions=3, interview_style="Behavioral")
    evaluation, follow_up = controller.submit_answer("random blue banana cricket whatever")

    assert evaluation.overall_score < 0.20
    assert "did not answer" in evaluation.feedback
    assert evaluation.follow_up_category == "Relevance clarification"
    assert follow_up is not None
    assert original.question in follow_up.question


def test_five_hr_styles_have_distinct_opening_and_behavior():
    styles = ["General HR", "Behavioral", "Leadership", "Situational", "Stress Interview"]
    openings = []
    for style in styles:
        controller = HRController(backend=CuratedHRBackend())
        question = controller.start(max_questions=3, interview_style=style)
        openings.append((question.id, question.question))
        assert question.interview_style == style

    assert len(set(openings)) == len(styles)


def test_evidence_rich_answer_scores_above_generic_answer():
    backend = CuratedHRBackend()
    question = HRQuestion(
        id="leadership",
        question="Tell me about a project you led and its result.",
        category="Leadership",
        interview_style="Leadership",
    )
    strong = backend.evaluate(
        question,
        "During my internship I led a team project. I analyzed the bottleneck, proposed two options, "
        "aligned the manager and team, and implemented batching. We reduced latency by 42 percent, "
        "and I learned to surface the risk earlier.",
    )
    generic = backend.evaluate(question, "I worked hard and the team did a good job.")

    assert strong.overall_score > generic.overall_score + 0.25
    assert "Strong" in strong.feedback or "shows" in strong.feedback


def test_irrelevant_reply_to_follow_up_is_not_silently_ignored():
    controller = HRController(backend=CuratedHRBackend())
    controller.start(max_questions=4, interview_style="Behavioral")
    _, first_probe = controller.submit_answer("The team made the decision and I do not know the result.")
    assert first_probe is not None
    assert first_probe.id.startswith("hr-followup-")

    evaluation, clarification = controller.submit_answer("random blue banana cricket whatever")
    assert evaluation.follow_up_category == "Relevance clarification"
    assert clarification is not None
    assert clarification.category == "Relevance clarification"
