import uuid
from datetime import datetime

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from app.models import Follow, MediaAsset, Post, PostMedia, Tag, post_tags
from app.schemas.post import PostCreate


class PostRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, post_id: uuid.UUID) -> Post | None:
        return self.db.get(Post, post_id)

    def add(
        self,
        author_id: uuid.UUID,
        data: PostCreate,
        assets: list[MediaAsset],
        tags: list[Tag],
        place_id: uuid.UUID | None = None,
        location_text: str | None = None,
    ) -> Post:
        post = Post(
            author_id=author_id,
            body=data.body,
            location_text=location_text if location_text is not None else data.location_text,
            place_id=place_id,
            tags=tags,
            media=[
                PostMedia(
                    asset_id=asset.id,
                    media_type="image",
                    url=asset.url,
                    width=asset.width,
                    height=asset.height,
                    alt_text=m.alt_text,
                    position=i,
                )
                for i, (m, asset) in enumerate(zip(data.media, assets, strict=True))
            ],
        )
        self.db.add(post)
        self.db.commit()
        self.db.refresh(post)
        return post

    def count_by_author(self, author_id: uuid.UUID) -> int:
        return self.db.scalar(select(func.count()).where(Post.author_id == author_id)) or 0

    def delete(self, post: Post) -> None:
        self.db.delete(post)
        self.db.commit()

    def feed(
        self,
        *,
        limit: int,
        before: tuple[datetime, uuid.UUID] | None,
        following_of: uuid.UUID | None = None,
        author_id: uuid.UUID | None = None,
        place_id: uuid.UUID | None = None,
        tag: str | None = None,
    ) -> list[Post]:
        """Newest-first keyset page. Fetches `limit` rows; callers pass limit+1 to detect more."""
        stmt = select(Post).order_by(Post.created_at.desc(), Post.id.desc()).limit(limit)
        if author_id is not None:
            stmt = stmt.where(Post.author_id == author_id)
        if place_id is not None:
            stmt = stmt.where(Post.place_id == place_id)
        if tag is not None:
            stmt = stmt.where(
                Post.id.in_(
                    select(post_tags.c.post_id)
                    .join(Tag, Tag.id == post_tags.c.tag_id)
                    .where(Tag.name == tag)
                )
            )
        if following_of is not None:  # "Following" feed: people I follow, plus myself
            followed = select(Follow.followee_id).where(Follow.follower_id == following_of)
            stmt = stmt.where(or_(Post.author_id.in_(followed), Post.author_id == following_of))
        if before is not None:
            created_at, post_id = before
            stmt = stmt.where(
                or_(
                    Post.created_at < created_at,
                    and_(Post.created_at == created_at, Post.id < post_id),
                )
            )
        return list(self.db.execute(stmt).unique().scalars())
