import uuid
from datetime import UTC, datetime

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator

from app.schemas.author import AuthorRead, author_dict


class LikeState(BaseModel):
    liked: bool
    like_count: int


class SaveState(BaseModel):
    saved: bool


class FollowState(BaseModel):
    following: bool
    followers_count: int


class CommentCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=1000)

    @field_validator("body")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("comment cannot be empty")
        return v


class CommentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    post_id: uuid.UUID
    body: str
    author: AuthorRead
    created_at: datetime
    is_mine: bool = False

    @field_validator("author", mode="before")
    @classmethod
    def _author(cls, user):
        return user if isinstance(user, dict) else author_dict(user)

    @field_serializer("created_at")
    def _utc(self, v: datetime) -> str:
        return (v if v.tzinfo else v.replace(tzinfo=UTC)).astimezone(UTC).isoformat()


class CommentPage(BaseModel):
    items: list[CommentRead]
    next_cursor: str | None


class UserSummary(BaseModel):
    """Compact public user card used in follower lists, search and Explore."""

    id: uuid.UUID
    username: str
    display_name: str | None
    avatar_url: str | None = None
    creator_type: str | None
    is_following: bool
    is_me: bool


class UserPage(BaseModel):
    items: list[UserSummary]
    next_cursor: str | None
