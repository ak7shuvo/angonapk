import secrets
import uuid
from datetime import datetime

from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import Follow, Story, StoryLike, StoryMedia, StorySave, Tag, story_tags
from app.models.story import STATUS_PUBLISHED


class StoryRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, story_id: uuid.UUID) -> Story | None:
        return self.db.get(Story, story_id)

    def get_by_slug(self, slug: str) -> Story | None:
        return (
            self.db.execute(select(Story).where(Story.slug == slug)).unique().scalar_one_or_none()
        )

    def published_count(self, author_id: uuid.UUID) -> int:
        return (
            self.db.scalar(
                select(func.count()).where(
                    Story.author_id == author_id, Story.status == STATUS_PUBLISHED
                )
            )
            or 0
        )

    def slug_exists(self, slug: str) -> bool:
        return self.db.scalar(select(Story.id).where(Story.slug == slug)) is not None

    def new_slug(self, base: str) -> str:
        for _ in range(8):
            slug = f"{base}-{secrets.token_hex(3)}"
            if not self.slug_exists(slug):
                return slug
        return f"{base}-{secrets.token_hex(8)}"

    def add(self, story: Story) -> Story:
        self.db.add(story)
        self.db.commit()
        self.db.refresh(story)
        return story

    def save(self, story: Story) -> Story:
        self.db.commit()
        self.db.refresh(story)
        return story

    def delete(self, story: Story) -> None:
        self.db.delete(story)
        self.db.commit()

    # --- listing -------------------------------------------------------------------

    def published_page(
        self,
        *,
        limit: int,
        before: tuple[datetime, uuid.UUID] | None,
        author_id: uuid.UUID | None = None,
        tag: str | None = None,
        place_id: uuid.UUID | None = None,
    ) -> list[Story]:
        stmt = (
            select(Story)
            .where(Story.status == STATUS_PUBLISHED)
            .order_by(Story.published_at.desc(), Story.id.desc())
            .limit(limit)
        )
        if author_id is not None:
            stmt = stmt.where(Story.author_id == author_id)
        if place_id is not None:
            stmt = stmt.where(Story.place_id == place_id)
        if tag is not None:
            stmt = stmt.where(
                Story.id.in_(
                    select(story_tags.c.story_id)
                    .join(Tag, Tag.id == story_tags.c.tag_id)
                    .where(Tag.name == tag)
                )
            )
        if before is not None:
            stamp, sid = before
            stmt = stmt.where(
                or_(
                    Story.published_at < stamp,
                    and_(Story.published_at == stamp, Story.id < sid),
                )
            )
        return list(self.db.scalars(stmt).unique())

    def mine_page(
        self,
        author_id: uuid.UUID,
        *,
        status: str | None,
        limit: int,
        before: tuple[datetime, uuid.UUID] | None,
    ) -> list[Story]:
        stmt = (
            select(Story)
            .where(Story.author_id == author_id)
            .order_by(Story.updated_at.desc(), Story.id.desc())
            .limit(limit)
        )
        if status is not None:
            stmt = stmt.where(Story.status == status)
        if before is not None:
            stamp, sid = before
            stmt = stmt.where(
                or_(Story.updated_at < stamp, and_(Story.updated_at == stamp, Story.id < sid))
            )
        return list(self.db.scalars(stmt).unique())

    def related_candidates(
        self, story: Story, tag_names: list[str], limit: int = 60
    ) -> list[Story]:
        conditions = [Story.author_id == story.author_id]
        if tag_names:
            conditions.append(
                Story.id.in_(
                    select(story_tags.c.story_id)
                    .join(Tag, Tag.id == story_tags.c.tag_id)
                    .where(Tag.name.in_(tag_names))
                )
            )
        if story.place_id is not None:
            conditions.append(Story.place_id == story.place_id)
        stmt = (
            select(Story)
            .where(Story.status == STATUS_PUBLISHED, Story.id != story.id, or_(*conditions))
            .order_by(Story.published_at.desc())
            .limit(limit)
        )
        return list(self.db.scalars(stmt).unique())

    # --- engagement ----------------------------------------------------------------

    def stats(
        self, story_ids: list[uuid.UUID], viewer_id: uuid.UUID | None
    ) -> dict[uuid.UUID, tuple[int, bool, bool]]:
        """story id -> (like_count, liked_by_viewer, saved_by_viewer)."""
        out = {sid: [0, False, False] for sid in story_ids}
        if not story_ids:
            return {}
        for sid, n in self.db.execute(
            select(StoryLike.story_id, func.count())
            .where(StoryLike.story_id.in_(story_ids))
            .group_by(StoryLike.story_id)
        ):
            out[sid][0] = n
        if viewer_id is not None:
            for sid in self.db.scalars(
                select(StoryLike.story_id).where(
                    StoryLike.user_id == viewer_id, StoryLike.story_id.in_(story_ids)
                )
            ):
                out[sid][1] = True
            for sid in self.db.scalars(
                select(StorySave.story_id).where(
                    StorySave.user_id == viewer_id, StorySave.story_id.in_(story_ids)
                )
            ):
                out[sid][2] = True
        return {k: (v[0], v[1], v[2]) for k, v in out.items()}

    def followed_authors(self, viewer_id: uuid.UUID, author_ids: list[uuid.UUID]) -> set[uuid.UUID]:
        if not author_ids:
            return set()
        return set(
            self.db.scalars(
                select(Follow.followee_id).where(
                    Follow.follower_id == viewer_id, Follow.followee_id.in_(author_ids)
                )
            )
        )

    def _add_link(self, model, user_id, story_id) -> bool:
        if self.db.get(model, (user_id, story_id)) is not None:
            return False
        try:
            with self.db.begin_nested():
                self.db.add(model(user_id=user_id, story_id=story_id))
                self.db.flush()
        except IntegrityError:
            return False
        self.db.commit()
        return True

    def _remove_link(self, model, user_id, story_id) -> bool:
        res = self.db.execute(
            delete(model).where(model.user_id == user_id, model.story_id == story_id)
        )
        self.db.commit()
        return res.rowcount > 0

    def like(self, user_id, story_id) -> bool:
        return self._add_link(StoryLike, user_id, story_id)

    def unlike(self, user_id, story_id) -> bool:
        return self._remove_link(StoryLike, user_id, story_id)

    def save_story(self, user_id, story_id) -> bool:
        return self._add_link(StorySave, user_id, story_id)

    def unsave_story(self, user_id, story_id) -> bool:
        return self._remove_link(StorySave, user_id, story_id)

    def like_count(self, story_id: uuid.UUID) -> int:
        return self.db.scalar(select(func.count()).where(StoryLike.story_id == story_id)) or 0

    def saved_page(
        self, user_id: uuid.UUID, *, limit: int, before: tuple[datetime, uuid.UUID] | None
    ) -> list[tuple[Story, datetime]]:
        stmt = (
            select(Story, StorySave.created_at)
            .join(StorySave, StorySave.story_id == Story.id)
            .where(StorySave.user_id == user_id, Story.status == STATUS_PUBLISHED)
            .order_by(StorySave.created_at.desc(), Story.id.desc())
            .limit(limit)
        )
        if before is not None:
            stamp, sid = before
            stmt = stmt.where(
                or_(
                    StorySave.created_at < stamp,
                    and_(StorySave.created_at == stamp, Story.id < sid),
                )
            )
        return [(s, c) for s, c in self.db.execute(stmt).unique()]


__all__ = ["StoryMedia", "StoryRepository"]
