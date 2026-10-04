from fastapi import APIRouter

from app.api.deps import AuthSvc, CurrentUser
from app.schemas.profile import ProfileUpdate
from app.schemas.user import UserRead

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserRead)
def read_me(user: CurrentUser) -> UserRead:
    return user


@router.patch("/me/profile", response_model=UserRead)
def update_my_profile(data: ProfileUpdate, user: CurrentUser, auth: AuthSvc) -> UserRead:
    return auth.update_profile(user, data)
