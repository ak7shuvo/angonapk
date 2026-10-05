import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.user import User

TARGET_TYPES = ("post", "story", "user", "comment")
REASONS = ("spam", "harassment", "hate", "nudity", "violence", "misinformation", "other")
STATUS_OPEN = "open"
STATUS_REVIEWING = "reviewing"
STATUS_RESOLVED = "resolved"
STATUS_DISMISSED = "dismissed"
STATUSES = (STATUS_OPEN, STATUS_REVIEWING, STATUS_RESOLVED, STATUS_DISMISSED)


def _now() -> datetime:
    return datetime.now(UTC)


class Report(Base):
    """A user's report of a post, story, comment or profile for moderators.

    `target_id` is deliberately not a foreign key (the target is one of several
    tables), so a report outlives deletion of the thing reported: moderators keep
    the record and the list marks the target as gone.
    """

    __tablename__ = "reports"
    __table_args__ = (
        # One report per person per target: the duplicate-spam guard.
        UniqueConstraint("reporter_id", "target_type", "target_id", name="uq_reports_once"),
        Index("ix_reports_status_created", "status", "created_at", "id"),
        Index("ix_reports_target", "target_type", "target_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    reporter_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    target_type: Mapped[str] = mapped_column(String(16))
    target_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    reason: Mapped[str] = mapped_column(String(24))
    details: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), default=STATUS_OPEN)
    resolution_note: Mapped[str | None] = mapped_column(Text)
    reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="SET NULL")
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    reporter: Mapped[User] = relationship(foreign_keys=[reporter_id], lazy="joined")
