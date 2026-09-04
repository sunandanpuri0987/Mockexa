import requests
import json
import os
import jwt
import time
from pprint import pprint

BASE_URL = "http://127.0.0.1:8000"
TEST_SECRET = os.environ.get(
    "SUPABASE_JWT_SECRET", "dev-secret-do-not-use-in-production-replace-with-supabase-jwt-secret"
)

def get_token(user_id="user-1"):
    payload = {"sub": user_id, "exp": time.time() + 3600}
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")

def get_expired_token(user_id="user-1"):
    payload = {"sub": user_id, "exp": time.time() - 3600}
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")

def run():
    print("=== 4. HEALTH ===")
    r_health = requests.get(f"{BASE_URL}/health")
    print("GET /health -> Status:", r_health.status_code)
    print(r_health.json())

    print("\n=== 5. AUTHENTICATION ===")
    # A. Tech without Auth
    r_no_auth_tech = requests.post(f"{BASE_URL}/technical/start", json={"name": "x", "target_role": "y", "experience": "z"})
    print("A. Tech without auth -> Status:", r_no_auth_tech.status_code)

    # B. GD without Auth
    r_no_auth_gd = requests.post(f"{BASE_URL}/gd/start", json={"topic": "x"})
    print("B. GD without auth -> Status:", r_no_auth_gd.status_code)

    # C. Valid local JWT
    headers1 = {"Authorization": f"Bearer {get_token('user-A')}"}
    r_valid = requests.post(f"{BASE_URL}/technical/start", headers=headers1, json={"name": "A", "target_role": "B", "experience": "C"})
    print("C. Valid JWT -> Status:", r_valid.status_code)
    session_a = r_valid.json().get("session_id")

    # D. Invalid JWT
    r_invalid = requests.post(f"{BASE_URL}/technical/start", headers={"Authorization": "Bearer bad.token.here"}, json={"name": "A", "target_role": "B", "experience": "C"})
    print("D. Invalid JWT -> Status:", r_invalid.status_code)

    # E. Expired JWT
    r_exp = requests.post(f"{BASE_URL}/technical/start", headers={"Authorization": f"Bearer {get_expired_token('user-A')}"}, json={"name": "A", "target_role": "B", "experience": "C"})
    print("E. Expired JWT -> Status:", r_exp.status_code)

    # F. Cross-user session access
    headers2 = {"Authorization": f"Bearer {get_token('user-B')}"}
    r_cross = requests.post(f"{BASE_URL}/technical/answer", headers=headers2, json={"session_id": session_a, "answer": "test"})
    print("F. Cross-user access -> Status:", r_cross.status_code)


    print("\n=== 6. TECHNICAL END-TO-END ===")
    print("Starting tech interview...")
    r_t_start = requests.post(f"{BASE_URL}/technical/start", headers=headers1, json={"name": "Dev", "target_role": "Backend", "experience": "Senior", "selected_domains": ["Algorithms"]})
    print("Start Status:", r_t_start.status_code)
    t_session_id = r_t_start.json().get("session_id")
    print("Session ID:", t_session_id)
    
    print("Answering question...")
    r_t_ans = requests.post(f"{BASE_URL}/technical/answer", headers=headers1, json={"session_id": t_session_id, "answer": "I would use a hash map for O(1) lookups."})
    print("Answer Status:", r_t_ans.status_code)
    ans_data = r_t_ans.json()
    print("Evaluation:", ans_data.get("evaluation"))
    
    # Normally we'd do 3 rounds, let's just finish early if possible or just do finish
    print("Finishing tech interview...")
    r_t_fin = requests.post(f"{BASE_URL}/technical/finish/{t_session_id}", headers=headers1)
    print("Finish Status:", r_t_fin.status_code)
    print("Final Report Keys:", r_t_fin.json().keys() if r_t_fin.status_code == 200 else r_t_fin.text)


    print("\n=== 7. GD END-TO-END ===")
    print("Starting GD...")
    r_gd_start = requests.post(f"{BASE_URL}/gd/start", headers=headers1, json={"topic": "Space exploration", "num_rounds": 1, "mode": "balanced"})
    print("Start Status:", r_gd_start.status_code)
    gd_session_id = r_gd_start.json().get("session_id")

    print("Responding to GD...")
    r_gd_ans = requests.post(f"{BASE_URL}/gd/respond", headers=headers1, json={"session_id": gd_session_id})
    print("Respond Status:", r_gd_ans.status_code)
    if r_gd_ans.status_code == 200:
        turn = r_gd_ans.json().get("turn", {})
        print("Speaker:", turn.get("speaker"), "| Claim:", turn.get("claim"))
    
    print("Finishing GD...")
    r_gd_fin = requests.post(f"{BASE_URL}/gd/finish/{gd_session_id}", headers=headers1)
    print("Finish Status:", r_gd_fin.status_code)
    if r_gd_fin.status_code == 200:
        print("Metrics:", r_gd_fin.json().get("metrics"))


    print("\n=== 10. API CONTRACT CHECK ===")
    r_docs = requests.get(f"{BASE_URL}/docs")
    print("GET /docs Status:", r_docs.status_code)
    r_openapi = requests.get(f"{BASE_URL}/openapi.json")
    print("GET /openapi.json Status:", r_openapi.status_code)


    print("\n=== 11. CORS / ERROR HANDLING ===")
    print("CORS Preflight:")
    r_opts = requests.options(f"{BASE_URL}/health", headers={"Origin": "http://localhost:3000", "Access-Control-Request-Method": "GET"})
    print("Status:", r_opts.status_code, "| ACAO:", r_opts.headers.get("access-control-allow-origin"))
    
    print("Malformed Request (422):")
    r_mal = requests.post(f"{BASE_URL}/technical/start", headers=headers1, json={"invalid": "payload"})
    print("Status:", r_mal.status_code)
    print("JSON:", r_mal.json())

if __name__ == "__main__":
    run()
