import re
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.schemas.user import UserRead

USERNAME_RE = re.compile(r"^[a-z0-9_]{3,30}$")
# Names that would impersonate the platform or collide with routes.
RESERVED_USERNAMES = frozenset(
    {
        "admin",
        "administrator",
        "angon",
        "api",
        "support",
        "system",
        "root",
        "moderator",
        "staff",
        "null",
        "undefined",
        "help",
        "official",
    }
)


class RegisterRequest(BaseModel):
    email: EmailStr
    username: str = Field(min_length=3, max_length=30)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("email")
    @classmethod
    def _lower_email(cls, v: str) -> str:
        return v.strip().lower()

    @field_validator("username")
    @classmethod
    def _normalize_username(cls, v: str) -> str:
        v = v.strip().lower()
        if not USERNAME_RE.fullmatch(v):
            raise ValueError("username may only contain letters, digits and underscores (3-30)")
        if v in RESERVED_USERNAMES:
            raise ValueError("this username is reserved")
        return v


class LoginRequest(BaseModel):
    # Email or username.
    identifier: str = Field(min_length=1, max_length=320)
    password: str = Field(min_length=1, max_length=128)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_at: datetime
    user: UserRead
