import uuid
from datetime import UTC, datetime

from sqlalchemy import JSON, DateTime, ForeignKey, Index, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.user import User


def _now() -> datetime:
    return datetime.now(UTC)


class Notification(Base):
    """An in-app notification for `recipient`.

    `type` is an open string so new kinds (bookings, community experiences,
    messages, moderation) need no schema change: clients render known types and
    fall back to `data.title` / `data.body` for unknown ones.
    """

    __tablename__ = "notifications"
    __table_args__ = (
        Index("ix_notifications_recipient_created", "recipient_id", "created_at", "id"),
        Index("ix_notifications_recipient_read", "recipient_id", "read_at"),
        Index("ix_notifications_target", "target_type", "target_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    recipient_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE")
    )
    # Who caused it; null for system notices.
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE")
    )
    type: Mapped[str] = mapped_column(String(32))  # like | comment | follow | ...
    target_type: Mapped[str | None] = mapped_column(String(32))  # post | story | comment | user
    target_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    actor: Mapped[User | None] = relationship(foreign_keys=[actor_id], lazy="joined")

    @property
    def is_read(self) -> bool:
        return self.read_at is not None
