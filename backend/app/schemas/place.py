import uuid
from datetime import UTC, datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator


class PlaceBrief(BaseModel):
    """Compact place reference embedded in posts and stories."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    slug: str
    name: str
    name_local: str | None = None


class PlaceSummary(PlaceBrief):
    cover_url: str | None
    latitude: float
    longitude: float
    division: str | None
    district: str | None
    post_count: int = 0
    story_count: int = 0
    # Present only for proximity searches.
    distance_km: float | None = None


class PlaceRead(PlaceSummary):
    description: str
    country: str
    upazila: str | None
    metadata: dict[str, Any] = Field(validation_alias="meta")
    created_at: datetime

    @field_serializer("created_at")
    def _utc(self, v: datetime) -> str:
        return (v if v.tzinfo else v.replace(tzinfo=UTC)).astimezone(UTC).isoformat()


class PlaceList(BaseModel):
    items: list[PlaceSummary]
    total: int


class PlaceCreate(BaseModel):
    """Admin-only."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=2, max_length=120)
    name_local: str | None = Field(default=None, max_length=120)
    description: str = Field(default="", max_length=5000)
    cover_url: str | None = Field(default=None, max_length=2048)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    country: str = Field(default="Bangladesh", max_length=80)
    division: str | None = Field(default=None, max_length=80)
    district: str | None = Field(default=None, max_length=80)
    upazila: str | None = Field(default=None, max_length=80)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("name")
    @classmethod
    def _name(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 2:
            raise ValueError("name is too short")
        return v

    @field_validator("name_local", "division", "district", "upazila")
    @classmethod
    def _optional_text(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None

    @field_validator("cover_url")
    @classmethod
    def _cover(cls, v: str | None) -> str | None:
        if v is not None and not (v.startswith(("https://", "http://")) or v.startswith("/media/")):
            raise ValueError("cover_url must be http(s) or a /media/ path")
        return v


class PlaceUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=2, max_length=120)
    name_local: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=5000)
    cover_url: str | None = Field(default=None, max_length=2048)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    division: str | None = Field(default=None, max_length=80)
    district: str | None = Field(default=None, max_length=80)
    upazila: str | None = Field(default=None, max_length=80)
    metadata: dict[str, Any] | None = None


class PhotoRead(BaseModel):
    id: uuid.UUID
    url: str
    width: int | None
    height: int | None
    post_id: uuid.UUID


class PhotoPage(BaseModel):
    items: list[PhotoRead]
    next_cursor: str | None
