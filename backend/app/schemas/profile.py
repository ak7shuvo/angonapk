from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field, field_validator


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
    is_complete: bool


class ProfileUpdate(BaseModel):
    """Partial update: only fields present in the request body are changed."""

    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(default=None, max_length=80)
    bio: str | None = Field(default=None, max_length=500)
    location: str | None = Field(default=None, max_length=120)
    creator_type: CreatorType | None = None

    @field_validator("display_name", "bio", "location")
    @classmethod
    def _strip(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None
