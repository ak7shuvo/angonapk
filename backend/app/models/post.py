from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.media import MediaAsset
from app.models.tag import Tag, post_tags

if TYPE_CHECKING:
    from app.models.user import User


def _now() -> datetime:
    return datetime.now(UTC)


class Post(Base):
    """Short social content: text and/or media, with an optional location."""

    __tablename__ = "posts"
    __table_args__ = (
        # Backs keyset pagination of the feed (newest first).
        Index("ix_posts_created_at_id", "created_at", "id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    author_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    body: Mapped[str | None] = mapped_column(Text)
    # Free-text location as typed by the author ("Jaflong, Sylhet").
    location_text: Mapped[str | None] = mapped_column(String(120))
    # Reserved for the Place system (Phase 09). Deliberately has no foreign key
    # yet because the `places` table does not exist; the FK is added then.
    place_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now
    )

    author: Mapped[User] = relationship(lazy="joined")
    tags: Mapped[list[Tag]] = relationship(secondary=post_tags, order_by=Tag.name, lazy="selectin")
    media: Mapped[list[PostMedia]] = relationship(
        back_populates="post",
        cascade="all, delete-orphan",
        order_by="PostMedia.position",
        lazy="selectin",
    )


class PostMedia(Base):
    __tablename__ = "post_media"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    post_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("posts.id", ondelete="CASCADE"), index=True
    )
    # Set for uploaded media; null for development seed rows that only carry a URL.
    asset_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="SET NULL"), index=True
    )
    media_type: Mapped[str] = mapped_column(String(16))  # "image" | "video"
    # Absolute http(s) URL or a storage-relative path such as "/media/...".
    url: Mapped[str] = mapped_column(String(2048))
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    alt_text: Mapped[str | None] = mapped_column(String(300))
    position: Mapped[int] = mapped_column(Integer, default=0)

    post: Mapped[Post] = relationship(back_populates="media")
    asset: Mapped[MediaAsset | None] = relationship(lazy="joined")
