import uuid
from datetime import UTC, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator

from app.models.report import REASONS, STATUSES, TARGET_TYPES
from app.schemas.author import AuthorRead, author_dict

TargetType = Literal[TARGET_TYPES]  # type: ignore[valid-type]
Reason = Literal[REASONS]  # type: ignore[valid-type]
ReportStatus = Literal[STATUSES]  # type: ignore[valid-type]


class ReportCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_type: TargetType
    target_id: uuid.UUID
    reason: Reason
    details: str | None = Field(default=None, max_length=1000)

    @field_validator("details")
    @classmethod
    def _blank_is_none(cls, v: str | None) -> str | None:
        v = (v or "").strip()
        return v or None


class ReportReceipt(BaseModel):
    """What the reporter sees: confirmation only, never moderation internals."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    target_type: str
    target_id: uuid.UUID
    reason: str
    status: str


class ReportUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: ReportStatus
    resolution_note: str | None = Field(default=None, max_length=1000)

    @field_validator("resolution_note")
    @classmethod
    def _blank_is_none(cls, v: str | None) -> str | None:
        v = (v or "").strip()
        return v or None


class ReportAdminRead(BaseModel):
    """A report as moderators see it, with a short preview of the target."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    reporter: AuthorRead
    target_type: str
    target_id: uuid.UUID
    reason: str
    details: str | None
    status: str
    resolution_note: str | None
    reviewed_at: datetime | None
    created_at: datetime
    # Filled by the service: {"exists": bool, "author": AuthorRead | None, "preview": str | None}
    target: dict[str, Any] | None = None
    report_count_for_target: int = 1

    @field_validator("reporter", mode="before")
    @classmethod
    def _reporter(cls, user):
        return author_dict(user) if not isinstance(user, dict) else user

    @field_serializer("created_at", "reviewed_at")
    def _utc(self, v: datetime | None) -> str | None:
        if v is None:
            return None
        return (v if v.tzinfo else v.replace(tzinfo=UTC)).astimezone(UTC).isoformat()


class ReportAdminPage(BaseModel):
    items: list[ReportAdminRead]
    next_cursor: str | None
