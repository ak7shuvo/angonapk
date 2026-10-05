import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import Comment, Follow, Post, PostLike, PostSave, User


@dataclass
class Engagement:
    like_count: int = 0
    comment_count: int = 0
    liked: bool = False
    saved: bool = False


class SocialRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # --- engagement counts (batched: 4 queries per page, not per post) --------

    def engagement(
        self, post_ids: list[uuid.UUID], viewer_id: uuid.UUID | None
    ) -> dict[uuid.UUID, Engagement]:
        result = {pid: Engagement() for pid in post_ids}
        if not post_ids:
            return result
        likes = self.db.execute(
            select(PostLike.post_id, func.count())
            .where(PostLike.post_id.in_(post_ids))
            .group_by(PostLike.post_id)
        )
        for pid, n in likes:
            result[pid].like_count = n
        comments = self.db.execute(
            select(Comment.post_id, func.count())
            .where(Comment.post_id.in_(post_ids))
            .group_by(Comment.post_id)
        )
        for pid, n in comments:
            result[pid].comment_count = n
        if viewer_id is not None:
            for pid in self.db.scalars(
                select(PostLike.post_id).where(
                    PostLike.user_id == viewer_id, PostLike.post_id.in_(post_ids)
                )
            ):
                result[pid].liked = True
            for pid in self.db.scalars(
                select(PostSave.post_id).where(
                    PostSave.user_id == viewer_id, PostSave.post_id.in_(post_ids)
                )
            ):
                result[pid].saved = True
        return result

    # --- likes / saves ----------------------------------------------------------

    def _add_link(self, model, user_id: uuid.UUID, post_id: uuid.UUID) -> bool:
        """Insert (user, post) if absent. Returns True when a row was created."""
        if self.db.get(model, (user_id, post_id)) is not None:
            return False
        try:
            with self.db.begin_nested():
                self.db.add(model(user_id=user_id, post_id=post_id))
                self.db.flush()
        except IntegrityError:  # concurrent duplicate: the row exists, which is the goal
            return False
        self.db.commit()
        return True

    def _remove_link(self, model, user_id: uuid.UUID, post_id: uuid.UUID) -> bool:
        result = self.db.execute(
            delete(model).where(model.user_id == user_id, model.post_id == post_id)
        )
        self.db.commit()
        return result.rowcount > 0

    def like(self, user_id, post_id) -> bool:
        return self._add_link(PostLike, user_id, post_id)

    def unlike(self, user_id, post_id) -> bool:
        return self._remove_link(PostLike, user_id, post_id)

    def save(self, user_id, post_id) -> bool:
        return self._add_link(PostSave, user_id, post_id)

    def unsave(self, user_id, post_id) -> bool:
        return self._remove_link(PostSave, user_id, post_id)

    def like_count(self, post_id: uuid.UUID) -> int:
        return self.db.scalar(select(func.count()).where(PostLike.post_id == post_id)) or 0

    def saved_posts(
        self, user_id: uuid.UUID, *, limit: int, before: tuple[datetime, uuid.UUID] | None
    ) -> list[tuple[Post, datetime]]:
        stmt = (
            select(Post, PostSave.created_at)
            .join(PostSave, PostSave.post_id == Post.id)
            .where(PostSave.user_id == user_id)
            .order_by(PostSave.created_at.desc(), Post.id.desc())
            .limit(limit)
        )
        if before is not None:
            stamp, pid = before
            stmt = stmt.where(
                or_(
                    PostSave.created_at < stamp,
                    and_(PostSave.created_at == stamp, Post.id < pid),
                )
            )
        return [(p, c) for p, c in self.db.execute(stmt).unique()]

    # --- comments ---------------------------------------------------------------

    def add_comment(self, post_id: uuid.UUID, author_id: uuid.UUID, body: str) -> Comment:
        comment = Comment(post_id=post_id, author_id=author_id, body=body)
        self.db.add(comment)
        self.db.commit()
        self.db.refresh(comment)
        return comment

    def comment_ids(self, post_id: uuid.UUID) -> list[uuid.UUID]:
        return list(self.db.scalars(select(Comment.id).where(Comment.post_id == post_id)))

    def get_comment(self, comment_id: uuid.UUID) -> Comment | None:
        return self.db.get(Comment, comment_id)

    def delete_comment(self, comment: Comment) -> None:
        self.db.delete(comment)
        self.db.commit()

    def comments_page(
        self, post_id: uuid.UUID, *, limit: int, after: tuple[datetime, uuid.UUID] | None
    ) -> list[Comment]:
        """Oldest first, so a conversation reads top to bottom."""
        stmt = (
            select(Comment)
            .where(Comment.post_id == post_id)
            .order_by(Comment.created_at.asc(), Comment.id.asc())
            .limit(limit)
        )
        if after is not None:
            stamp, cid = after
            stmt = stmt.where(
                or_(
                    Comment.created_at > stamp,
                    and_(Comment.created_at == stamp, Comment.id > cid),
                )
            )
        return list(self.db.scalars(stmt).unique())

    # --- follows ----------------------------------------------------------------

    def follow(self, follower_id: uuid.UUID, followee_id: uuid.UUID) -> bool:
        if self.db.get(Follow, (follower_id, followee_id)) is not None:
            return False
        try:
            with self.db.begin_nested():
                self.db.add(Follow(follower_id=follower_id, followee_id=followee_id))
                self.db.flush()
        except IntegrityError:
            return False
        self.db.commit()
        return True

    def unfollow(self, follower_id: uuid.UUID, followee_id: uuid.UUID) -> bool:
        result = self.db.execute(
            delete(Follow).where(
                Follow.follower_id == follower_id, Follow.followee_id == followee_id
            )
        )
        self.db.commit()
        return result.rowcount > 0

    def followers_count(self, user_id: uuid.UUID) -> int:
        return self.db.scalar(select(func.count()).where(Follow.followee_id == user_id)) or 0

    def following_count(self, user_id: uuid.UUID) -> int:
        return self.db.scalar(select(func.count()).where(Follow.follower_id == user_id)) or 0

    def following_ids(self, user_id: uuid.UUID, candidates: list[uuid.UUID]) -> set[uuid.UUID]:
        if not candidates:
            return set()
        return set(
            self.db.scalars(
                select(Follow.followee_id).where(
                    Follow.follower_id == user_id, Follow.followee_id.in_(candidates)
                )
            )
        )

    def _follow_page(self, *, anchor, other, user_id, limit, before) -> list[tuple[User, datetime]]:
        stmt = (
            select(User, Follow.created_at)
            .join(Follow, other == User.id)
            .where(anchor == user_id)
            .order_by(Follow.created_at.desc(), User.id.desc())
            .limit(limit)
        )
        if before is not None:
            stamp, uid = before
            stmt = stmt.where(
                or_(
                    Follow.created_at < stamp,
                    and_(Follow.created_at == stamp, User.id < uid),
                )
            )
        return [(u, c) for u, c in self.db.execute(stmt).unique()]

    def followers_page(self, user_id, *, limit, before):
        return self._follow_page(
            anchor=Follow.followee_id,
            other=Follow.follower_id,
            user_id=user_id,
            limit=limit,
            before=before,
        )

    def following_page(self, user_id, *, limit, before):
        return self._follow_page(
            anchor=Follow.follower_id,
            other=Follow.followee_id,
            user_id=user_id,
            limit=limit,
            before=before,
        )
