from __future__ import annotations

import math
import uuid
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Table,
    Text,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.media import MediaAsset
from app.models.tag import Tag
from app.models.user import User

if TYPE_CHECKING:
    pass


def _now() -> datetime:
    return datetime.now(UTC)


story_tags = Table(
    "story_tags",
    Base.metadata,
    Column("story_id", Uuid, ForeignKey("stories.id", ondelete="CASCADE"), primary_key=True),
    Column(
        "tag_id", Integer, ForeignKey("tags.id", ondelete="CASCADE"), primary_key=True, index=True
    ),
)

STATUS_DRAFT = "draft"
STATUS_PUBLISHED = "published"


class Story(Base):
    """Long-form storytelling: a title, a cover, and editorial content."""

    __tablename__ = "stories"
    __table_args__ = (
        Index("ix_stories_status_published", "status", "published_at", "id"),
        Index("ix_stories_author_updated", "author_id", "updated_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    author_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(200))
    slug: Mapped[str] = mapped_column(String(240), unique=True, index=True)
    # Lightweight markup: paragraphs, "## heading", "> quote", "![caption](asset:<id>)".
    content: Mapped[str] = mapped_column(Text, default="")
    cover_asset_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="SET NULL"), index=True
    )
    location_text: Mapped[str | None] = mapped_column(String(120))
    # Reserved for the Place system (FK added with the places table).
    place_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    status: Mapped[str] = mapped_column(String(16), default=STATUS_DRAFT)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now
    )

    author: Mapped[User] = relationship(lazy="joined")
    cover_asset: Mapped[MediaAsset | None] = relationship(lazy="joined")
    tags: Mapped[list[Tag]] = relationship(secondary=story_tags, order_by=Tag.name, lazy="selectin")
    media: Mapped[list[StoryMedia]] = relationship(
        back_populates="story",
        cascade="all, delete-orphan",
        order_by="StoryMedia.position",
        lazy="selectin",
    )

    @property
    def is_published(self) -> bool:
        return self.status == STATUS_PUBLISHED

    @property
    def reading_minutes(self) -> int:
        return max(1, math.ceil(len(self.content.split()) / 200))


class StoryMedia(Base):
    """An uploaded image embedded in the story body."""

    __tablename__ = "story_media"

    story_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("stories.id", ondelete="CASCADE"), primary_key=True
    )
    asset_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    position: Mapped[int] = mapped_column(Integer, default=0)

    story: Mapped[Story] = relationship(back_populates="media")
    asset: Mapped[MediaAsset] = relationship(lazy="joined")


class StoryLike(Base):
    __tablename__ = "story_likes"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    story_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("stories.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class StorySave(Base):
    __tablename__ = "story_saves"
    __table_args__ = (Index("ix_story_saves_user_created", "user_id", "created_at"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    story_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("stories.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
