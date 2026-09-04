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

def run_verification():
    print("--- 1. Testing Unauthenticated Request ---")
    resp = requests.post(f"{BASE_URL}/gd/start", json={"topic": "Test"})
    print(f"Status: {resp.status_code} (Expected 401)")
    
    print("\n--- 2. Starting GD Session ---")
    headers1 = {"Authorization": f"Bearer {get_token('user-1')}"}
    resp1 = requests.post(
        f"{BASE_URL}/gd/start",
        json={"topic": "Should remote work be mandated?", "num_rounds": 1, "mode": "balanced"},
        headers=headers1
    )
    print(f"Status: {resp1.status_code}")
    data1 = resp1.json()
    session_id = data1.get("session_id")
    print(f"Session ID: {session_id}")
    print("Topic Analysis:")
    pprint(data1.get("topic_analysis"))
    
    print("\n--- 3. Testing Session Isolation ---")
    headers2 = {"Authorization": f"Bearer {get_token('user-2')}"}
    resp2 = requests.post(
        f"{BASE_URL}/gd/respond",
        json={"session_id": session_id},
        headers=headers2
    )
    print(f"Cross-user status: {resp2.status_code} (Expected 404)")
    
    print("\n--- 4. Continuing Discussion (Turns) ---")
    for i in range(4): # One full round with 4 participants
        print(f"\nTurn {i+1}:")
        turn_resp = requests.post(
            f"{BASE_URL}/gd/respond",
            json={"session_id": session_id},
            headers=headers1
        )
        print(f"Status: {turn_resp.status_code}")
        turn_data = turn_resp.json()
        if turn_data.get("finished"):
            print("Discussion finished early!")
            break
        turn = turn_data.get("turn", {})
        print(f"Speaker: {turn.get('speaker')} (Action: {turn.get('action')})")
        print(f"Claim: {turn.get('claim')}")
    
    print("\n--- 5. Finishing Discussion ---")
    finish_resp = requests.post(
        f"{BASE_URL}/gd/finish/{session_id}",
        headers=headers1
    )
    print(f"Status: {finish_resp.status_code}")
    finish_data = finish_resp.json()
    print("Metrics:")
    pprint(finish_data.get("metrics"))
    print("Summary:")
    pprint(finish_data.get("summary"))
    
    print("\n--- 6. Verifying Technical Route ---")
    tech_resp = requests.post(
        f"{BASE_URL}/technical/start",
        json={"name": "Test", "target_role": "SWE", "experience": "Beginner", "selected_domains": ["Algorithms"]},
        headers=headers1
    )
    print(f"Technical Start Status: {tech_resp.status_code} (Expected 200)")

if __name__ == "__main__":
    run_verification()
