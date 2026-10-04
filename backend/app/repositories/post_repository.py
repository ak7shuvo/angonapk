import uuid
from datetime import datetime

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.models import Post, PostMedia
from app.schemas.post import PostCreate


class PostRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, post_id: uuid.UUID) -> Post | None:
        return self.db.get(Post, post_id)

    def add(self, author_id: uuid.UUID, data: PostCreate) -> Post:
        post = Post(
            author_id=author_id,
            body=data.body,
            location_text=data.location_text,
            media=[
                PostMedia(
                    media_type=m.type.value,
                    url=m.url,
                    width=m.width,
                    height=m.height,
                    alt_text=m.alt_text,
                    position=i,
                )
                for i, m in enumerate(data.media)
            ],
        )
        self.db.add(post)
        self.db.commit()
        self.db.refresh(post)
        return post

    def delete(self, post: Post) -> None:
        self.db.delete(post)
        self.db.commit()

    def feed(self, *, limit: int, before: tuple[datetime, uuid.UUID] | None) -> list[Post]:
        """Newest-first keyset page. Fetches `limit` rows; callers pass limit+1 to detect more."""
        stmt = select(Post).order_by(Post.created_at.desc(), Post.id.desc()).limit(limit)
        if before is not None:
            created_at, post_id = before
            stmt = stmt.where(
                or_(
                    Post.created_at < created_at,
                    and_(Post.created_at == created_at, Post.id < post_id),
                )
            )
        return list(self.db.execute(stmt).unique().scalars())
