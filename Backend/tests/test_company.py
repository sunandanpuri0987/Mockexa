from __future__ import annotations

from app.config import get_settings
from app.data.company_questions import COMPANIES, QUESTIONS
from app.main import app
from app.controllers.company_controller import evaluate_company_fast


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
