import uuid
from datetime import UTC, datetime
from enum import StrEnum

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_serializer,
    field_validator,
    model_validator,
)

from app.schemas.author import AuthorRead, author_dict
from app.schemas.place import PlaceBrief
from app.schemas.tags import normalize_tags

MAX_BODY = 2000
MAX_MEDIA = 10


class MediaType(StrEnum):
    IMAGE = "image"
    VIDEO = "video"


class MediaCreate(BaseModel):
    """Reference to a previously uploaded asset (POST /media)."""

    model_config = ConfigDict(extra="forbid")

    asset_id: uuid.UUID
    alt_text: str | None = Field(default=None, max_length=300)


class PostCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str | None = Field(default=None, max_length=MAX_BODY)
    location_text: str | None = Field(default=None, max_length=120)
    media: list[MediaCreate] = Field(default_factory=list, max_length=MAX_MEDIA)
    tags: list[str] = Field(default_factory=list, max_length=20)
    place_id: uuid.UUID | None = None

    @field_validator("body", "location_text")
    @classmethod
    def _strip(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None

    @field_validator("tags")
    @classmethod
    def _tags(cls, v: list[str]) -> list[str]:
        return normalize_tags(v)

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


class PostRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    body: str | None
    location_text: str | None
    place_id: uuid.UUID | None
    place: PlaceBrief | None
    media: list[MediaRead]
    tags: list[str]
    author: AuthorRead
    created_at: datetime
    updated_at: datetime
    # Viewer-relative engagement, filled in by PostService.present().
    like_count: int = 0
    comment_count: int = 0
    liked_by_me: bool = False
    saved_by_me: bool = False
    following_author: bool = False

    @field_validator("tags", mode="before")
    @classmethod
    def _tag_names(cls, v):
        return [t if isinstance(t, str) else t.name for t in v]

    @field_validator("author", mode="before")
    @classmethod
    def _author_summary(cls, user):
        return user if isinstance(user, dict) else author_dict(user)

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
