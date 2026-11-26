from __future__ import annotations

from app.config import get_settings
from app.data.company_questions import COMPANIES, QUESTIONS
from app.main import app
from app.controllers.company_controller import evaluate_company_fast
from app.controllers.technical_controller import AnswerAnalysis


def test_company_catalog_is_source_backed_and_complete(client, auth_headers):
    response = client.get("/company/companies", headers=auth_headers)
    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 12
    assert {item["id"] for item in payload} == {company.id for company in COMPANIES}
    assert all(item["question_count"] >= 4 for item in payload)
    assert all(question.source_url.startswith("https://") for question in QUESTIONS)
    assert len({question.id for question in QUESTIONS}) == len(QUESTIONS)


def test_questions_filter_and_do_not_leak_answer(client, auth_headers):
    response = client.get(
        "/company/google/questions?categories=System%20Design&shuffle=false",
        headers=auth_headers,
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload
    assert all(question["category"] == "System Design" for question in payload)
    assert all("answer_outline" not in question for question in payload)
    assert all("focus_points" not in question for question in payload)


def test_start_shuffles_filtered_bank(monkeypatch, client, auth_headers):
    monkeypatch.setattr(
        "app.controllers.company_controller.random.SystemRandom.shuffle",
        lambda _self, values: values.reverse(),
    )
    response = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "amazon", "categories": ["Behavioral"], "question_count": 2},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["total_questions"] == 2
    assert payload["question"]["category"] == "Behavioral"


def test_company_practice_answer_and_finish(client, auth_headers):
    base_settings = get_settings()
    app.dependency_overrides[get_settings] = lambda: base_settings.model_copy(
        update={"use_gemini": False}
    )
    try:
        started = client.post(
            "/company/start",
            headers=auth_headers,
            json={"company_id": "microsoft", "question_count": 1},
        )
        assert started.status_code == 200
        session_id = started.json()["session_id"]

        answered = client.post(
            "/company/answer",
            headers=auth_headers,
            json={
                "session_id": session_id,
                "answer": "I would define the invariant, handle edge cases, and explain time complexity because correctness must be measurable.",
            },
        )
        assert answered.status_code == 200
        body = answered.json()
        assert body["completed"] is True
        assert body["next_question"] is None
        assert body["reviewed_question"]["answer_outline"]
        assert body["evaluation"]["feedback"]

        finished = client.post(f"/company/finish/{session_id}", headers=auth_headers)
        assert finished.status_code == 200
        report = finished.json()
        assert report["company_name"] == "Microsoft"
        assert report["questions_answered"] == 1
        assert 0 <= report["overall_score"] <= 100

        history = client.get("/sessions", headers=auth_headers)
        assert history.status_code == 200
        history_item = next(item for item in history.json() if item["id"] == session_id)
        assert history_item["kind"] == "company"
        assert history_item["topic"] == "Microsoft Practice"

        detail = client.get(f"/sessions/{session_id}", headers=auth_headers)
        assert detail.status_code == 200
        assert detail.json()["report"]["category_scores"]
        assert any(entry["speaker"] == "You" for entry in detail.json()["transcript"])
    finally:
        app.dependency_overrides.pop(get_settings, None)


def test_company_sessions_are_owner_scoped(client, auth_headers, second_auth_headers):
    started = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "apple", "question_count": 2},
    )
    session_id = started.json()["session_id"]
    response = client.post(
        "/company/answer",
        headers=second_auth_headers,
        json={"session_id": session_id, "answer": "A sufficiently detailed answer."},
    )
    assert response.status_code == 404


def test_invalid_company_and_category_are_rejected(client, auth_headers):
    unknown = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "unknown", "question_count": 5},
    )
    assert unknown.status_code == 404
    invalid_category = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "google", "categories": ["Magic"], "question_count": 5},
    )
    assert invalid_category.status_code == 422
    invalid_list_filter = client.get(
        "/company/google/questions?categories=Magic",
        headers=auth_headers,
    )
    assert invalid_list_filter.status_code == 422


def test_start_normalizes_company_and_category_case(client, auth_headers):
    response = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "Google", "categories": ["system design"], "question_count": 1},
    )
    assert response.status_code == 200
    assert response.json()["question"]["category"] == "System Design"


def test_finish_is_idempotent_for_network_retries(client, auth_headers):
    started = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "google", "question_count": 1},
    )
    session_id = started.json()["session_id"]
    answered = client.post(
        "/company/answer",
        headers=auth_headers,
        json={"session_id": session_id, "answer": "I would first clarify requirements, explain tradeoffs, test edge cases, and measure the result."},
    )
    assert answered.status_code == 200

    first = client.post(f"/company/finish/{session_id}", headers=auth_headers)
    retry = client.post(f"/company/finish/{session_id}", headers=auth_headers)
    assert first.status_code == 200
    assert retry.status_code == 200
    assert retry.json() == first.json()


def test_answer_retry_is_idempotent_and_cannot_advance_twice(client, auth_headers):
    started = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "google", "question_count": 2},
    ).json()
    payload = {
        "session_id": started["session_id"],
        "question_id": started["question"]["id"],
        "answer": "I would clarify the requirements, explain the tradeoffs, test edge cases, and measure the result.",
    }
    first = client.post("/company/answer", headers=auth_headers, json=payload)
    stale_retry = client.post("/company/answer", headers=auth_headers, json=payload)

    assert first.status_code == 200
    assert stale_retry.status_code == 200
    assert stale_retry.json() == first.json()
    next_question = first.json()["next_question"]
    second = client.post(
        "/company/answer",
        headers=auth_headers,
        json={
            "session_id": started["session_id"],
            "question_id": next_question["id"],
            "answer": "I would use a structured approach, justify each decision, test edge cases, and measure the outcome.",
        },
    )
    assert second.status_code == 200
    report = client.post(f"/company/finish/{started['session_id']}", headers=auth_headers)
    assert report.status_code == 200
    assert report.json()["questions_answered"] == 2


def test_incomplete_session_cannot_grant_final_report(client, auth_headers):
    started = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "amazon", "question_count": 2},
    ).json()
    answered = client.post(
        "/company/answer",
        headers=auth_headers,
        json={
            "session_id": started["session_id"],
            "question_id": started["question"]["id"],
            "answer": "I would clarify the goal, explain tradeoffs, validate edge cases, and measure the result.",
        },
    )
    assert answered.status_code == 200
    early_finish = client.post(f"/company/finish/{started['session_id']}", headers=auth_headers)
    assert early_finish.status_code == 409


def test_unknown_role_does_not_silently_fall_back_to_all_roles(client, auth_headers):
    response = client.post(
        "/company/start",
        headers=auth_headers,
        json={"company_id": "google", "role": "astronaut", "question_count": 1},
    )
    assert response.status_code == 422


def test_fast_evaluator_is_not_a_fixed_baseline():
    question = next(item for item in QUESTIONS if item.id == "google-global-messaging")
    weak = evaluate_company_fast(question, "I am not sure about this answer.")
    partial = evaluate_company_fast(
        question,
        "I would expose an API, store messages in a database, and use a queue because retries and failure handling are required.",
    )
    strong = evaluate_company_fast(
        question,
        "First I would define delivery and latency requirements. WebSocket gateways publish to a partitioned message queue. "
        "Messages are persisted before acknowledgement, partitioned by conversation for ordering, retried idempotently, "
        "and monitored for delivery lag. Replication handles failure; the design is O(1) per message excluding fan-out.",
    )
    assert weak.overall_score < partial.overall_score < strong.overall_score
    assert len({weak.overall_score, partial.overall_score, strong.overall_score}) == 3


def test_deep_ai_feedback_is_returned_to_the_client(monkeypatch, client, auth_headers):
    ai_analysis = AnswerAnalysis(
        classification="MOSTLY_CORRECT",
        correctness=0.82,
        completeness=0.74,
        relevance=0.91,
        reasoning=0.79,
        missing_concepts=("failure recovery",),
        misconceptions=(),
        overall_score=0.81,
        feedback="Strong structure; add a concrete failure-recovery strategy.",
    )
    monkeypatch.setattr(
        "app.routers.company.GeminiTechnicalBackend.evaluate",
        lambda _self, _question, _answer: ai_analysis,
    )
    base_settings = get_settings()
    app.dependency_overrides[get_settings] = lambda: base_settings.model_copy(
        update={"use_gemini": True, "gemini_api_key": "test-key"}
    )
    try:
        started = client.post(
            "/company/start",
            headers=auth_headers,
            json={
                "company_id": "google",
                "categories": ["System Design"],
                "question_count": 1,
                "evaluation_mode": "ai",
            },
        ).json()
        answered = client.post(
            "/company/answer",
            headers=auth_headers,
            json={
                "session_id": started["session_id"],
                "question_id": started["question"]["id"],
                "answer": "I would define requirements, APIs, storage, ordering, retries, and monitoring.",
            },
        )
        assert answered.status_code == 200
        assert answered.json()["evaluation"]["feedback"] == ai_analysis.feedback
    finally:
        app.dependency_overrides.pop(get_settings, None)


def test_deep_ai_failure_falls_back_to_fast_evaluation(monkeypatch, client, auth_headers):
    monkeypatch.setattr(
        "app.routers.company.GeminiTechnicalBackend.evaluate",
        lambda _self, _question, _answer: (_ for _ in ()).throw(RuntimeError("provider unavailable")),
    )
    base_settings = get_settings()
    app.dependency_overrides[get_settings] = lambda: base_settings.model_copy(
        update={"use_gemini": True, "gemini_api_key": "test-key"}
    )
    try:
        started = client.post(
            "/company/start",
            headers=auth_headers,
            json={"company_id": "amazon", "question_count": 1, "evaluation_mode": "ai"},
        ).json()
        answered = client.post(
            "/company/answer",
            headers=auth_headers,
            json={
                "session_id": started["session_id"],
                "question_id": started["question"]["id"],
                "answer": "I would clarify requirements, explain tradeoffs, test edge cases, and measure the result.",
            },
        )
        assert answered.status_code == 200
        body = answered.json()
        assert 0.0 <= body["evaluation"]["overall_score"] <= 1.0
        assert body["evaluation"]["feedback"]
    finally:
        app.dependency_overrides.pop(get_settings, None)
