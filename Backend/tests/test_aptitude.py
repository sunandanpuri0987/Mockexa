from app.data.aptitude_questions import CATEGORIES, QUESTIONS


def test_aptitude_catalog_has_four_balanced_categories():
    assert set(CATEGORIES) == {
        "Data Interpretation", "Logical Reasoning", "Quantitative Aptitude", "Verbal Ability"
    }
    assert len(QUESTIONS) == 40
    for category in CATEGORIES:
        assert len([question for question in QUESTIONS if question.category == category]) == 10
    assert all(len(question.options) == 4 for question in QUESTIONS)
    assert all(0 <= question.correct_index <= 3 for question in QUESTIONS)


def test_categories_require_auth_and_return_catalog(client, auth_headers):
    assert client.get("/aptitude/categories").status_code in (401, 403)
    response = client.get("/aptitude/categories", headers=auth_headers)
    assert response.status_code == 200
    assert response.json() == list(CATEGORIES)


def test_complete_aptitude_round_is_scored_and_saved(client, auth_headers):
    started = client.post("/aptitude/start", headers=auth_headers, json={
        "categories": ["Quantitative Aptitude"],
        "question_count": 6,
        "duration_minutes": 10,
    })
    assert started.status_code == 200
    body = started.json()
    session_id = body["session_id"]
    question = body["question"]
    total = body["total_questions"]
    correct = 0

    while question is not None:
        source = next(item for item in QUESTIONS if item.id == question["id"])
        answered = client.post("/aptitude/answer", headers=auth_headers, json={
            "session_id": session_id,
            "question_id": question["id"],
            "selected_index": source.correct_index,
        })
        assert answered.status_code == 200
        answer_body = answered.json()
        assert answer_body["is_correct"] is True
        assert answer_body["explanation"]
        correct += 1
        question = answer_body["next_question"]

    assert correct == total == 6
    finished = client.post(f"/aptitude/finish/{session_id}", headers=auth_headers)
    assert finished.status_code == 200
    report = finished.json()
    assert report["overall_score"] == 100
    assert report["correct"] == 6
    assert report["passed"] is True

    history = client.get("/sessions", headers=auth_headers)
    assert history.status_code == 200
    assert any(item["id"] == session_id and item["kind"] == "aptitude" for item in history.json())
    detail = client.get(f"/sessions/{session_id}", headers=auth_headers)
    assert detail.status_code == 200
    assert detail.json()["report"]["category_scores"]["Quantitative Aptitude"] == 100


def test_answer_retry_is_idempotent(client, auth_headers):
    started = client.post("/aptitude/start", headers=auth_headers, json={
        "question_count": 5, "duration_minutes": 5,
    }).json()
    payload = {
        "session_id": started["session_id"],
        "question_id": started["question"]["id"],
        "selected_index": 0,
    }
    first = client.post("/aptitude/answer", headers=auth_headers, json=payload)
    second = client.post("/aptitude/answer", headers=auth_headers, json=payload)
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()


def test_sessions_are_owner_scoped(client, auth_headers, second_auth_headers):
    started = client.post("/aptitude/start", headers=auth_headers, json={
        "question_count": 5, "duration_minutes": 5,
    }).json()
    response = client.post("/aptitude/answer", headers=second_auth_headers, json={
        "session_id": started["session_id"],
        "question_id": started["question"]["id"],
        "selected_index": 0,
    })
    assert response.status_code == 404


def test_invalid_category_and_stale_question_are_rejected(client, auth_headers):
    invalid = client.post("/aptitude/start", headers=auth_headers, json={
        "categories": ["Astrology"], "question_count": 5, "duration_minutes": 5,
    })
    assert invalid.status_code == 422

    started = client.post("/aptitude/start", headers=auth_headers, json={
        "question_count": 5, "duration_minutes": 5,
    }).json()
    stale = client.post("/aptitude/answer", headers=auth_headers, json={
        "session_id": started["session_id"],
        "question_id": "not-the-current-question",
        "selected_index": 0,
    })
    assert stale.status_code == 409


def test_difficulty_is_an_upper_bound_and_keeps_category_round_viable(client, auth_headers):
    response = client.post("/aptitude/start", headers=auth_headers, json={
        "categories": ["Verbal Ability"],
        "difficulty": 3,
        "question_count": 5,
        "duration_minutes": 5,
    })
    assert response.status_code == 200
    assert response.json()["total_questions"] == 5

    easy = client.post("/aptitude/start", headers=auth_headers, json={
        "categories": ["Verbal Ability"],
        "difficulty": 1,
        "question_count": 10,
        "duration_minutes": 5,
    })
    assert easy.status_code == 200
    assert easy.json()["total_questions"] == 10


def test_finish_early_counts_unanswered_and_is_idempotent(client, auth_headers):
    started = client.post("/aptitude/start", headers=auth_headers, json={
        "question_count": 5, "duration_minutes": 5,
    }).json()
    first = client.post(f"/aptitude/finish/{started['session_id']}", headers=auth_headers)
    second = client.post(f"/aptitude/finish/{started['session_id']}", headers=auth_headers)
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert first.json()["attempted"] == 0
    assert first.json()["unanswered"] == 5
