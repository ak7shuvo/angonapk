import uuid
from datetime import UTC, datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator


class CreatorType(StrEnum):
    TRAVELER = "traveler"
    STORYTELLER = "storyteller"
    BLOGGER = "blogger"
    PHOTOGRAPHER = "photographer"
    VIDEOGRAPHER = "videographer"
    LOCAL_STORYTELLER = "local_storyteller"
    RESEARCHER = "researcher"
    TOURISM_BUSINESS = "tourism_business"
    GUIDE = "guide"
    COMMUNITY_ORGANIZATION = "community_organization"


class ProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    display_name: str | None
    bio: str | None
    location: str | None
    creator_type: CreatorType | None
    avatar_url: str | None
    cover_url: str | None
    is_complete: bool


class ProfileUpdate(BaseModel):
    """Partial update: only fields present in the request body are changed."""

    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(default=None, max_length=80)
    bio: str | None = Field(default=None, max_length=500)
    location: str | None = Field(default=None, max_length=120)
    creator_type: CreatorType | None = None
    # Ids from POST /media. Send null to remove the image.
    avatar_media_id: uuid.UUID | None = None
    cover_media_id: uuid.UUID | None = None

    @field_validator("display_name", "bio", "location")
    @classmethod
    def _strip(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None


class ProfileCounts(BaseModel):
    posts: int
    stories: int
    followers: int
    following: int
    places: int


class PublicProfile(BaseModel):
    """What anyone can see about a user (no email)."""

    id: uuid.UUID
    username: str
    display_name: str | None
    bio: str | None
    location: str | None
    creator_type: CreatorType | None
    avatar_url: str | None
    cover_url: str | None
    joined_at: datetime
    counts: ProfileCounts
    is_following: bool
    is_me: bool

    @field_serializer("joined_at")
    def _utc(self, v: datetime) -> str:
        return (v if v.tzinfo else v.replace(tzinfo=UTC)).astimezone(UTC).isoformat()
