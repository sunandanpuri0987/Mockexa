from pydantic import BaseModel, ConfigDict, Field
from typing import List, Optional, Any, Dict

class GDStartRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    topic: str = Field(min_length=3, max_length=180)
    num_rounds: int = Field(default=4, ge=1, le=10)
    duration_minutes: Optional[int] = Field(default=None, ge=5, le=30)
    mode: str = Field(default="balanced", pattern="^(balanced|consensus)$")
    resume_context: Optional[str] = None
    job_description: Optional[str] = None

class GDTurnResponse(BaseModel):
    speaker: str
    round: int
    action: str
    target: Optional[str]
    position: float
    claim: str
    response: str
    confidence: float
    issue: str

class GDStartResponse(BaseModel):
    session_id: str
    topic_analysis: Dict[str, Any]
    participants: List[Dict[str, Any]]

class GDRespondRequest(BaseModel):
    session_id: str
    user_contribution: Optional[str] = None
    conclude: bool = False

class GDRespondResponse(BaseModel):
    session_id: str
    turn: Optional[GDTurnResponse]
    finished: bool

class GDFinishResponse(BaseModel):
    session_id: str
    metrics: Dict[str, float]
    summary: Dict[str, Any]


class GDFinishRequest(BaseModel):
    interruption_count: int = Field(default=0, ge=0, le=50)


# Friends GD is deliberately separate from the AI-panel session contract. A
# room can be shared by several authenticated users and is synchronised by the
# lightweight status endpoint (the iOS client polls while the room is open).
class FriendsGDCreateRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    topic: str = Field(min_length=3, max_length=180)
    duration_minutes: int = Field(default=10, ge=5, le=30)
    mode: str = Field(default="balanced", pattern="^(balanced|consensus)$")
    max_participants: int = Field(default=8, ge=3, le=12)


class FriendsGDJoinRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    room_code: str = Field(min_length=6, max_length=6, pattern="^[A-Za-z0-9]{6}$")


class FriendsGDReadyRequest(BaseModel):
    ready: bool = True


class FriendsGDContributionRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    text: str = Field(min_length=3, max_length=1200)


class FriendsGDMatchmakeRequest(BaseModel):
    mode: str = Field(default="balanced", pattern="^(balanced|consensus)$")
    duration_minutes: int = Field(default=10, ge=5, le=30)


class RewardRedeemRequest(BaseModel):
    reward_id: str = Field(min_length=2, max_length=60)
