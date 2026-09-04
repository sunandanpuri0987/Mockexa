import pytest

from app.controllers.hr_controller import HRController, HREvaluation, HRQuestion, _HR_QUESTION_BANK

class MockHRBackend:
    def evaluate(self, question: HRQuestion, answer: str) -> HREvaluation:
        return HREvaluation(
            clarity=0.8, specificity=0.7, ownership=0.9, communication=0.8,
            teamwork=0.6, leadership=0.5, problem_solving=0.7,
            feedback="Good answer", overall_score=0.71
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
