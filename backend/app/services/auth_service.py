import uuid
from datetime import UTC, datetime

from sqlalchemy.exc import IntegrityError

from app.core.config import Settings
from app.core.security import (
    InvalidTokenError,
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)
from app.models import User
from app.repositories.user_repository import UserRepository
from app.schemas.auth import LoginRequest, RegisterRequest
from app.schemas.profile import ProfileUpdate


class DuplicateAccountError(Exception):
    def __init__(self, fields: dict[str, str]) -> None:
        self.fields = fields


class InvalidCredentialsError(Exception):
    pass


class AuthService:
    def __init__(self, repo: UserRepository, settings: Settings) -> None:
        self.repo = repo
        self.settings = settings

    def register(self, data: RegisterRequest) -> tuple[User, str, datetime]:
        email_taken, username_taken = self.repo.exists(email=data.email, username=data.username)
        if email_taken or username_taken:
            raise DuplicateAccountError(self._duplicate_fields(email_taken, username_taken))
        try:
            user = self.repo.add(
                email=data.email,
                username=data.username,
                password_hash=hash_password(data.password),
            )
        except IntegrityError:  # lost a race with a concurrent registration
            self.repo.db.rollback()
            email_taken, username_taken = self.repo.exists(email=data.email, username=data.username)
            raise DuplicateAccountError(
                self._duplicate_fields(email_taken, username_taken)
            ) from None
        token, expires = create_access_token(user.id, self.settings)
        return user, token, expires

    @staticmethod
    def _duplicate_fields(email_taken: bool, username_taken: bool) -> dict[str, str]:
        fields = {}
        if email_taken:
            fields["email"] = "Email is already registered"
        if username_taken:
            fields["username"] = "Username is already taken"
        return fields

    def login(self, data: LoginRequest) -> tuple[User, str, datetime]:
        user = self.repo.get_by_identifier(data.identifier)
        ok = verify_password(data.password, user.password_hash if user else None)
        if user is None or not ok or not user.is_active:
            raise InvalidCredentialsError
        token, expires = create_access_token(user.id, self.settings)
        return user, token, expires

    def authenticate(self, token: str) -> User:
        """Resolve a bearer token to an active user, or raise InvalidTokenError."""
        payload = decode_access_token(token, self.settings)
        if self.repo.is_token_revoked(payload["jti"]):
            raise InvalidTokenError("token revoked")
        try:
            user = self.repo.get(uuid.UUID(payload["sub"]))
        except ValueError as exc:
            raise InvalidTokenError("bad subject") from exc
        if user is None or not user.is_active:
            raise InvalidTokenError("unknown user")
        return user

    def logout(self, token: str) -> None:
        payload = decode_access_token(token, self.settings)
        self.repo.revoke_token(payload["jti"], datetime.fromtimestamp(payload["exp"], UTC))

    def update_profile(self, user: User, data: ProfileUpdate) -> User:
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(user.profile, field, value)
        return self.repo.save(user)
