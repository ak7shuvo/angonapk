import uuid
from datetime import datetime

from sqlalchemy import case, func, or_, select
from sqlalchemy.orm import Session

from app.models import (
    Comment,
    Follow,
    Post,
    PostLike,
    Profile,
    Story,
    StoryLike,
    Tag,
    User,
    post_tags,
    story_tags,
)
from app.models.story import STATUS_PUBLISHED
from app.repositories.place_repository import like_pattern


class ExploreRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # --- Explore ---------------------------------------------------------------------

    def category_counts(self, names: list[str]) -> dict[str, tuple[int, int]]:
        """tag name -> (posts, published stories)."""
        out = {n: [0, 0] for n in names}
        for name, n in self.db.execute(
            select(Tag.name, func.count(func.distinct(post_tags.c.post_id)))
            .join(post_tags, post_tags.c.tag_id == Tag.id)
            .where(Tag.name.in_(names))
            .group_by(Tag.name)
        ):
            out[name][0] = n
        for name, n in self.db.execute(
            select(Tag.name, func.count(func.distinct(story_tags.c.story_id)))
            .join(story_tags, story_tags.c.tag_id == Tag.id)
            .join(Story, Story.id == story_tags.c.story_id)
            .where(Tag.name.in_(names), Story.status == STATUS_PUBLISHED)
            .group_by(Tag.name)
        ):
            out[name][1] = n
        return {k: (v[0], v[1]) for k, v in out.items()}

    def trending_posts(self, *, since: datetime, limit: int) -> list[Post]:
        """Recent posts ranked by real engagement (likes x2 + comments x3), newest first on ties."""
        likes = (
            select(PostLike.post_id.label("pid"), func.count().label("n"))
            .group_by(PostLike.post_id)
            .subquery()
        )
        comments = (
            select(Comment.post_id.label("pid"), func.count().label("n"))
            .group_by(Comment.post_id)
            .subquery()
        )
        score = func.coalesce(likes.c.n, 0) * 2 + func.coalesce(comments.c.n, 0) * 3
        stmt = (
            select(Post)
            .outerjoin(likes, likes.c.pid == Post.id)
            .outerjoin(comments, comments.c.pid == Post.id)
            .where(Post.created_at >= since)
            .order_by(score.desc(), Post.created_at.desc(), Post.id.desc())
            .limit(limit)
        )
        return list(self.db.scalars(stmt).unique())

    def featured_stories(self, limit: int) -> list[Story]:
        likes = (
            select(StoryLike.story_id.label("sid"), func.count().label("n"))
            .group_by(StoryLike.story_id)
            .subquery()
        )
        stmt = (
            select(Story)
            .outerjoin(likes, likes.c.sid == Story.id)
            .where(Story.status == STATUS_PUBLISHED)
            .order_by(
                func.coalesce(likes.c.n, 0).desc(), Story.published_at.desc(), Story.id.desc()
            )
            .limit(limit)
        )
        return list(self.db.scalars(stmt).unique())

    def creators(self, *, exclude: uuid.UUID, limit: int) -> list[User]:
        """Active creators with a finished profile, most followed first."""
        followers = (
            select(Follow.followee_id.label("uid"), func.count().label("n"))
            .group_by(Follow.followee_id)
            .subquery()
        )
        stmt = (
            select(User)
            .join(Profile, Profile.user_id == User.id)
            .outerjoin(followers, followers.c.uid == User.id)
            .where(
                User.is_active.is_(True),
                User.id != exclude,
                Profile.display_name.is_not(None),
                Profile.creator_type.is_not(None),
            )
            .order_by(func.coalesce(followers.c.n, 0).desc(), User.created_at.desc())
            .limit(limit)
        )
        return list(self.db.scalars(stmt).unique())

    # --- Search ----------------------------------------------------------------------

    def search_users(self, q: str, *, limit: int, offset: int) -> list[User]:
        pat = like_pattern(q)
        lowered = q.lower()
        rank = case(
            (User.username == lowered, 0),
            (User.username.ilike(like_pattern(q)[1:], escape="\\"), 1),  # prefix
            else_=2,
        )
        stmt = (
            select(User)
            .outerjoin(Profile, Profile.user_id == User.id)
            .where(
                User.is_active.is_(True),
                or_(
                    User.username.ilike(pat, escape="\\"),
                    Profile.display_name.ilike(pat, escape="\\"),
                ),
            )
            .order_by(rank, User.username)
            .limit(limit)
            .offset(offset)
        )
        return list(self.db.scalars(stmt).unique())

    def search_stories(self, q: str, *, limit: int, offset: int) -> list[Story]:
        pat = like_pattern(q)
        tag_match = (
            select(story_tags.c.story_id)
            .join(Tag, Tag.id == story_tags.c.tag_id)
            .where(Tag.name == q.lower().lstrip("#"))
        )
        stmt = (
            select(Story)
            .where(
                Story.status == STATUS_PUBLISHED,
                or_(
                    Story.title.ilike(pat, escape="\\"),
                    Story.content.ilike(pat, escape="\\"),
                    Story.location_text.ilike(pat, escape="\\"),
                    Story.id.in_(tag_match),
                ),
            )
            .order_by(Story.published_at.desc(), Story.id.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(self.db.scalars(stmt).unique())

    def search_posts(self, q: str, *, limit: int, offset: int) -> list[Post]:
        pat = like_pattern(q)
        tag_match = (
            select(post_tags.c.post_id)
            .join(Tag, Tag.id == post_tags.c.tag_id)
            .where(Tag.name == q.lower().lstrip("#"))
        )
        stmt = (
            select(Post)
            .where(
                or_(
                    Post.body.ilike(pat, escape="\\"),
                    Post.location_text.ilike(pat, escape="\\"),
                    Post.id.in_(tag_match),
                )
            )
            .order_by(Post.created_at.desc(), Post.id.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(self.db.scalars(stmt).unique())
