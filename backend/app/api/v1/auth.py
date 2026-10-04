from fastapi import APIRouter, HTTPException, Response, status

from app.api.deps import AuthSvc, CurrentUser, Token
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse
from app.services.auth_service import DuplicateAccountError, InvalidCredentialsError

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(data: RegisterRequest, auth: AuthSvc) -> TokenResponse:
    try:
        user, token, expires = auth.register(data)
    except DuplicateAccountError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=[{"loc": ["body", f], "msg": m} for f, m in exc.fields.items()],
        ) from None
    return TokenResponse(access_token=token, expires_at=expires, user=user)


@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, auth: AuthSvc) -> TokenResponse:
    try:
        user, token, expires = auth.login(data)
    except InvalidCredentialsError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email/username or password",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    return TokenResponse(access_token=token, expires_at=expires, user=user)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(token: Token, _user: CurrentUser, auth: AuthSvc) -> Response:
    """Revokes the presented token server-side."""
    auth.logout(token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
