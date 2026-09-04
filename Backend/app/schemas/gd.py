from pydantic import BaseModel, Field
from typing import List, Optional, Any, Dict

class GDStartRequest(BaseModel):
    topic: str
    num_rounds: int = Field(default=4, ge=1, le=10)
    mode: str = Field(default="balanced", pattern="^(balanced|consensus)$")

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

class GDRespondResponse(BaseModel):
    session_id: str
    turn: Optional[GDTurnResponse]
    finished: bool

class GDFinishResponse(BaseModel):
    session_id: str
    metrics: Dict[str, float]
    summary: Dict[str, Any]
