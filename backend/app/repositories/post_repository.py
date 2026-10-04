import uuid
from datetime import datetime

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.models import Follow, MediaAsset, Post, PostMedia, Tag
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
    ) -> Post:
        post = Post(
            author_id=author_id,
            body=data.body,
            location_text=data.location_text,
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

    def delete(self, post: Post) -> None:
        self.db.delete(post)
        self.db.commit()

    def feed(
        self,
        *,
        limit: int,
        before: tuple[datetime, uuid.UUID] | None,
        following_of: uuid.UUID | None = None,
    ) -> list[Post]:
        """Newest-first keyset page. Fetches `limit` rows; callers pass limit+1 to detect more."""
        stmt = select(Post).order_by(Post.created_at.desc(), Post.id.desc()).limit(limit)
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
