import os
import requests
import jwt
from typing import Dict, Any

def run_verify():
    print("=== LIVE HR HTTP VERIFICATION ===")
    
    # 1. Start Server
    # Ensure uvicorn is running on 8000
    base_url = "http://127.0.0.1:8000"
    
    # 2. Check health and groq key
    try:
        health = requests.get(f"{base_url}/health").json()
        print(f"Health: {health}")
        if not health.get("groq_configured"):
            print("WARNING: GROQ_API_KEY is not configured in .env.")
            print("The HR endpoints require a REAL Groq API key.")
            print("You must add one to .env and restart uvicorn to test the live flow.")
            return
    except Exception as e:
        print(f"Failed to reach server: {e}")
        return

    # 3. Create a test JWT token
    test_secret = os.environ.get(
        "SUPABASE_JWT_SECRET", 
        "dev-secret-do-not-use-in-production-replace-with-supabase-jwt-secret"
    )
    token = jwt.encode({"sub": "test-live-user-hr"}, test_secret, algorithm="HS256")
    headers = {"Authorization": f"Bearer {token}"}

    print("\n[1] Testing POST /hr/start")
    start_resp = requests.post(f"{base_url}/hr/start", json={
        "name": "Live Test Candidate",
        "target_role": "SWE Intern",
        "experience": "Entry",
        "max_questions": 2
    }, headers=headers)
    
    if start_resp.status_code != 200:
        print(f"Failed to start HR session: {start_resp.status_code} {start_resp.text}")
        return
        
    start_data = start_resp.json()
    session_id = start_data["session_id"]
    question = start_data["question"]
    print(f"Started Session: {session_id}")
    print(f"First Question ({question['category']}): {question['question']}")

    print("\n[2] Testing POST /hr/answer (1/2)")
    ans1_resp = requests.post(f"{base_url}/hr/answer", json={
        "session_id": session_id,
        "answer": "I introduced myself to the team and read the documentation to get up to speed."
    }, headers=headers)
    
    if ans1_resp.status_code != 200:
        print(f"Failed to submit answer 1: {ans1_resp.status_code} {ans1_resp.text}")
        return
        
    ans1_data = ans1_resp.json()
    eval1 = ans1_data["evaluation"]
    print(f"Evaluation 1: Overall Score = {eval1['overall_score']}")
    print(f"Feedback 1: {eval1['feedback']}")
    
    next_q = ans1_data.get("next_question")
    if next_q:
        print(f"Next Question ({next_q['category']}): {next_q['question']}")

    print("\n[3] Testing POST /hr/answer (2/2)")
    ans2_resp = requests.post(f"{base_url}/hr/answer", json={
        "session_id": session_id,
        "answer": "I resolved the conflict by listening to their concerns and finding a middle ground."
    }, headers=headers)
    
    if ans2_resp.status_code != 200:
        print(f"Failed to submit answer 2: {ans2_resp.status_code} {ans2_resp.text}")
        return
        
    ans2_data = ans2_resp.json()
    eval2 = ans2_data["evaluation"]
    print(f"Evaluation 2: Overall Score = {eval2['overall_score']}")
    print(f"Feedback 2: {eval2['feedback']}")
    
    print(f"Completed: {ans2_data['completed']}")

    print("\n[4] Testing POST /hr/finish")
    finish_resp = requests.post(f"{base_url}/hr/finish/{session_id}", headers=headers)
    
    if finish_resp.status_code != 200:
        print(f"Failed to finish session: {finish_resp.status_code} {finish_resp.text}")
        return
        
    report = finish_resp.json()["report"]
    print("\n=== FINAL REPORT ===")
    print(f"Overall Score: {report['overall_score']}")
    print(f"Strengths: {', '.join(report['strengths'])}")
    print(f"Weaknesses: {', '.join(report['weaknesses'])}")
    print("Metrics:")
    for k, v in report['metrics'].items():
        print(f"  {k}: {v}")

if __name__ == "__main__":
    run_verify()
