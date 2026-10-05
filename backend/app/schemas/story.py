import re
import uuid
from datetime import UTC, datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator

from app.schemas.author import AuthorRead
from app.schemas.place import PlaceBrief
from app.schemas.tags import normalize_tags

MAX_CONTENT = 50_000
INLINE_IMAGE_RE = re.compile(r"!\[([^\]]*)\]\(asset:([0-9a-fA-F-]{36})\)")


class StoryStatus(StrEnum):
    DRAFT = "draft"
    PUBLISHED = "published"


def _strip_or_none(v: str | None) -> str | None:
    if v is None:
        return None
    v = v.strip()
    return v or None


class StoryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(max_length=200)
    content: str = Field(default="", max_length=MAX_CONTENT)
    cover_asset_id: uuid.UUID | None = None
    location_text: str | None = Field(default=None, max_length=120)
    tags: list[str] = Field(default_factory=list, max_length=20)
    place_id: uuid.UUID | None = None
    status: StoryStatus = StoryStatus.DRAFT

    @field_validator("title")
    @classmethod
    def _title(cls, v: str) -> str:
        return v.strip()

    @field_validator("location_text")
    @classmethod
    def _loc(cls, v):
        return _strip_or_none(v)

    @field_validator("tags")
    @classmethod
    def _tags(cls, v: list[str]) -> list[str]:
        return normalize_tags(v)


class StoryUpdate(BaseModel):
    """Partial update. Send `cover_asset_id: null` to remove the cover."""

    model_config = ConfigDict(extra="forbid")

    title: str | None = Field(default=None, max_length=200)
    content: str | None = Field(default=None, max_length=MAX_CONTENT)
    cover_asset_id: uuid.UUID | None = None
    location_text: str | None = Field(default=None, max_length=120)
    tags: list[str] | None = Field(default=None, max_length=20)
    place_id: uuid.UUID | None = None

    @field_validator("title")
    @classmethod
    def _title(cls, v):
        return None if v is None else v.strip()

    @field_validator("location_text")
    @classmethod
    def _loc(cls, v):
        return _strip_or_none(v)

    @field_validator("tags")
    @classmethod
    def _tags(cls, v):
        return None if v is None else normalize_tags(v)


class CoverRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    url: str
    width: int | None
    height: int | None


class StorySummary(BaseModel):
    """List item: everything but the full body."""

    id: uuid.UUID
    slug: str
    title: str
    summary: str
    cover: CoverRead | None
    location_text: str | None
    place_id: uuid.UUID | None
    place: PlaceBrief | None
    tags: list[str]
    status: StoryStatus
    published_at: datetime | None
    updated_at: datetime
    reading_minutes: int
    author: AuthorRead
    like_count: int = 0
    liked_by_me: bool = False
    saved_by_me: bool = False
    following_author: bool = False

    @field_serializer("published_at", "updated_at")
    def _utc(self, v: datetime | None) -> str | None:
        if v is None:
            return None
        return (v if v.tzinfo else v.replace(tzinfo=UTC)).astimezone(UTC).isoformat()


class StoryRead(StorySummary):
    content: str
    # Images referenced by `![caption](asset:<id>)` tokens in the content.
    media: list[CoverRead]


class StoryPage(BaseModel):
    items: list[StorySummary]
    next_cursor: str | None
