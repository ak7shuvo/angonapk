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

bearer_scheme = HTTPBearer(auto_error=False)

DbSession = Annotated[Session, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings)]


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
