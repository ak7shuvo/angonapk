import uuid
from datetime import UTC, datetime
from enum import StrEnum
from typing import Annotated

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    field_serializer,
    field_validator,
    model_validator,
)

MAX_BODY = 2000
MAX_MEDIA = 10


class MediaType(StrEnum):
    IMAGE = "image"
    VIDEO = "video"


def _check_media_url(v: str) -> str:
    v = v.strip()
    if not (v.startswith(("https://", "http://")) or v.startswith("/media/")):
        raise ValueError("url must be http(s) or a /media/ path")
    if " " in v or "\n" in v:
        raise ValueError("url must not contain whitespace")
    return v


MediaUrl = Annotated[str, Field(min_length=1, max_length=2048), AfterValidator(_check_media_url)]


class MediaCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: MediaType = MediaType.IMAGE
    url: MediaUrl
    width: int | None = Field(default=None, gt=0, le=20000)
    height: int | None = Field(default=None, gt=0, le=20000)
    alt_text: str | None = Field(default=None, max_length=300)


class PostCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str | None = Field(default=None, max_length=MAX_BODY)
    location_text: str | None = Field(default=None, max_length=120)
    media: list[MediaCreate] = Field(default_factory=list, max_length=MAX_MEDIA)

    @field_validator("body", "location_text")
    @classmethod
    def _strip(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None

    @model_validator(mode="after")
    def _needs_content(self) -> "PostCreate":
        if not self.body and not self.media:
            raise ValueError("a post needs text or at least one media item")
        return self


class MediaRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    type: MediaType = Field(validation_alias="media_type")
    url: str
    width: int | None
    height: int | None
    alt_text: str | None


class AuthorRead(BaseModel):
    """Public author summary embedded in posts. No email or private data."""

    id: uuid.UUID
    username: str
    display_name: str | None


class PostRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    body: str | None
    location_text: str | None
    # Reserved: linked Place (Phase 09). Always null for now.
    place_id: uuid.UUID | None
    media: list[MediaRead]
    author: AuthorRead
    created_at: datetime
    updated_at: datetime

    @field_validator("author", mode="before")
    @classmethod
    def _author_summary(cls, user):
        if isinstance(user, dict):
            return user
        profile = user.profile
        return {
            "id": user.id,
            "username": user.username,
            "display_name": profile.display_name if profile else None,
        }

    @field_serializer("created_at", "updated_at")
    def _utc(self, v: datetime) -> str:
        # SQLite returns naive datetimes; they are always stored as UTC.
        if v.tzinfo is None:
            v = v.replace(tzinfo=UTC)
        return v.astimezone(UTC).isoformat()


class FeedPage(BaseModel):
    items: list[PostRead]
    # Opaque; pass back as `cursor` to fetch the next (older) page. Null at the end.
    next_cursor: str | None
