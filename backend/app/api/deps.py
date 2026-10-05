from functools import lru_cache
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.security import InvalidTokenError
from app.db.session import get_db
from app.models import User
from app.repositories.user_repository import UserRepository
from app.services.auth_service import AuthService
from app.storage.base import StorageBackend
from app.storage.factory import build_storage

bearer_scheme = HTTPBearer(auto_error=False)

DbSession = Annotated[Session, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings)]


@lru_cache
def _build_storage() -> StorageBackend:
    return build_storage(get_settings())


def get_storage() -> StorageBackend:
    return _build_storage()


Storage = Annotated[StorageBackend, Depends(get_storage)]


def get_auth_service(db: DbSession, settings: AppSettings) -> AuthService:
    return AuthService(UserRepository(db), settings)


AuthSvc = Annotated[AuthService, Depends(get_auth_service)]

_UNAUTHORIZED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Not authenticated",
    headers={"WWW-Authenticate": "Bearer"},
)


def get_token(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> str:
    if creds is None:
        raise _UNAUTHORIZED
    return creds.credentials


Token = Annotated[str, Depends(get_token)]


def get_current_user(token: Token, auth: AuthSvc) -> User:
    try:
        return auth.authenticate(token)
    except InvalidTokenError:
        raise _UNAUTHORIZED from None


CurrentUser = Annotated[User, Depends(get_current_user)]


# --- service factories -------------------------------------------------------------
# (imported lazily-at-bottom to keep the import graph acyclic)
from app.repositories.media_repository import MediaRepository  # noqa: E402
from app.repositories.place_repository import PlaceRepository  # noqa: E402
from app.repositories.post_repository import PostRepository  # noqa: E402
from app.repositories.social_repository import SocialRepository  # noqa: E402
from app.repositories.tag_repository import TagRepository  # noqa: E402
from app.services.media_service import MediaService  # noqa: E402
from app.services.post_service import PostService  # noqa: E402
from app.services.social_service import SocialService  # noqa: E402


def get_media_service(db: DbSession, storage: Storage, settings: AppSettings) -> MediaService:
    return MediaService(MediaRepository(db), storage, settings)


Media = Annotated[MediaService, Depends(get_media_service)]


def get_post_service(db: DbSession, media: Media) -> PostService:
    return PostService(
        PostRepository(db), TagRepository(db), media, SocialRepository(db), PlaceRepository(db)
    )


Posts = Annotated[PostService, Depends(get_post_service)]


def get_social_service(db: DbSession) -> SocialService:
    return SocialService(SocialRepository(db), PostRepository(db), UserRepository(db))


Social = Annotated[SocialService, Depends(get_social_service)]


from app.repositories.story_repository import StoryRepository  # noqa: E402
from app.services.story_service import StoryService  # noqa: E402


def get_story_service(db: DbSession, media: Media) -> StoryService:
    return StoryService(
        StoryRepository(db), TagRepository(db), media, UserRepository(db), PlaceRepository(db)
    )


Stories = Annotated[StoryService, Depends(get_story_service)]


from app.services.profile_service import ProfileService  # noqa: E402


def get_profile_service(db: DbSession, media: Media) -> ProfileService:
    return ProfileService(
        UserRepository(db),
        media,
        SocialRepository(db),
        PostRepository(db),
        StoryRepository(db),
    )


Profiles = Annotated[ProfileService, Depends(get_profile_service)]


from app.services.place_service import PlaceService  # noqa: E402


def get_place_service(db: DbSession) -> PlaceService:
    return PlaceService(PlaceRepository(db), SocialRepository(db))


Places = Annotated[PlaceService, Depends(get_place_service)]


def get_admin_user(user: CurrentUser) -> User:
    """Authorisation for admin-only endpoints (role set by an operator, never by the API)."""
    if user.role != "admin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Admin access required")
    return user


AdminUser = Annotated[User, Depends(get_admin_user)]
