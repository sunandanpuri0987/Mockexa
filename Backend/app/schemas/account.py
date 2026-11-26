from pydantic import BaseModel


class AccountDeletionResponse(BaseModel):
    deleted: bool
    message: str
