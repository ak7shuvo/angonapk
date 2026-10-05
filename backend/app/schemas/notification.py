import uuid
from datetime import UTC, datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, field_serializer, field_validator

from app.schemas.author import AuthorRead, author_dict


class NotificationRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    type: str
    actor: AuthorRead | None
    target_type: str | None
    target_id: uuid.UUID | None
    data: dict[str, Any]
    is_read: bool
    created_at: datetime

    @field_validator("actor", mode="before")
    @classmethod
    def _actor(cls, user):
        if user is None or isinstance(user, dict):
            return user
        return author_dict(user)

    @field_serializer("created_at")
    def _utc(self, v: datetime) -> str:
        return (v if v.tzinfo else v.replace(tzinfo=UTC)).astimezone(UTC).isoformat()


class NotificationPage(BaseModel):
    items: list[NotificationRead]
    next_cursor: str | None


class UnreadCount(BaseModel):
    unread: int
