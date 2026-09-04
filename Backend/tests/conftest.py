import os
import jwt
import pytest
from dotenv import load_dotenv
from fastapi.testclient import TestClient

# Find the project root .env file and load it
env_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".env"))
if os.path.exists(env_path):
    load_dotenv(env_path)

# Set in-memory session mode for pytest unit tests to prevent dummy tokens hitting live Supabase API
os.environ["USE_SUPABASE_PERSISTENCE"] = "False"

TEST_SECRET = os.environ.get(
    "SUPABASE_JWT_SECRET", "dev-secret-do-not-use-in-production-replace-with-supabase-jwt-secret"
)

def get_test_token(user_id: str = "test-user-123") -> str:
    return jwt.encode({"sub": user_id}, TEST_SECRET, algorithm="HS256")

@pytest.fixture(autouse=True)
def clean_session_stores():
    from app.utils.session_store import technical_sessions, gd_sessions, hr_sessions, completed_sessions
    technical_sessions.clear()
    gd_sessions.clear()
    hr_sessions.clear()
    completed_sessions.clear()
    yield
    technical_sessions.clear()
    gd_sessions.clear()
    hr_sessions.clear()
    completed_sessions.clear()

@pytest.fixture
def client():
    from app.main import app
    return TestClient(app)

@pytest.fixture
def auth_headers():
    token = get_test_token("test-user-123")
    return {"Authorization": f"Bearer {token}"}

@pytest.fixture
def second_auth_headers():
    token = get_test_token("user-456-other")
    return {"Authorization": f"Bearer {token}"}

