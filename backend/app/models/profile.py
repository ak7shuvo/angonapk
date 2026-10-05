from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.media import MediaAsset

if TYPE_CHECKING:
    from app.models.user import User


def _now() -> datetime:
    return datetime.now(UTC)


class Profile(Base):
    """A user's traveller / creator identity. One per user."""

    __tablename__ = "profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    display_name: Mapped[str | None] = mapped_column(String(80))
    bio: Mapped[str | None] = mapped_column(Text)
    location: Mapped[str | None] = mapped_column(String(120))
    # See app.schemas.profile.CreatorType; kept a plain string so new roles need no migration.
    creator_type: Mapped[str | None] = mapped_column(String(32))
    avatar_asset_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="SET NULL"), index=True
    )
    cover_asset_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="SET NULL"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now
    )

    user: Mapped[User] = relationship(back_populates="profile")
    avatar_asset: Mapped[MediaAsset | None] = relationship(
        foreign_keys=[avatar_asset_id], lazy="joined"
    )
    cover_asset: Mapped[MediaAsset | None] = relationship(
        foreign_keys=[cover_asset_id], lazy="joined"
    )

    @property
    def avatar_url(self) -> str | None:
        return self.avatar_asset.url if self.avatar_asset else None

    @property
    def cover_url(self) -> str | None:
        return self.cover_asset.url if self.cover_asset else None

    @property
    def is_complete(self) -> bool:
        return bool(self.display_name and self.display_name.strip() and self.creator_type)
