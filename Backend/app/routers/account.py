from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user_id, get_raw_jwt_token
from app.repository import RepositoryError, SupabaseRepository
from app.schemas.account import AccountDeletionResponse


router = APIRouter(prefix="/account", tags=["account"])


@router.delete("", response_model=AccountDeletionResponse)
async def delete_account(
    user_id: str = Depends(get_current_user_id),
    raw_token: str = Depends(get_raw_jwt_token),
):
    """Permanently delete the caller's Mockexa cloud data and Auth identity."""
    try:
        deleted = await SupabaseRepository().delete_own_account(raw_token)
    except RepositoryError as exc:
        raise HTTPException(status_code=503, detail=f"Account deletion unavailable: {exc}") from exc
    if not deleted:
        raise HTTPException(status_code=409, detail=f"Account {user_id} could not be deleted")
    return AccountDeletionResponse(
        deleted=True,
        message="Account and associated cloud data were permanently deleted.",
    )
