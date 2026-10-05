import uuid
from datetime import datetime

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from app.models import MediaAsset, Place, Post, PostMedia, Story, User
from app.models.story import STATUS_PUBLISHED


def like_pattern(q: str) -> str:
    """Escape LIKE wildcards so user text is matched literally."""
    escaped = q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escaped}%"


class PlaceRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, place_id: uuid.UUID) -> Place | None:
        return self.db.get(Place, place_id)

    def get_by_slug(self, slug: str) -> Place | None:
        return self.db.scalar(select(Place).where(Place.slug == slug))

    def slug_exists(self, slug: str) -> bool:
        return self.db.scalar(select(Place.id).where(Place.slug == slug)) is not None

    def add(self, place: Place) -> Place:
        self.db.add(place)
        self.db.commit()
        self.db.refresh(place)
        return place

    def save(self, place: Place) -> Place:
        self.db.commit()
        self.db.refresh(place)
        return place

    def search(
        self,
        *,
        q: str | None = None,
        division: str | None = None,
        district: str | None = None,
        bbox: tuple[float, float, float, float] | None = None,
        limit: int = 50,
        offset: int = 0,
        order_by_name: bool = True,
        all_rows: bool = False,
    ) -> tuple[list[Place], int]:
        conditions = []
        if q:
            pat = like_pattern(q.strip())
            conditions.append(
                or_(
                    Place.name.ilike(pat, escape="\\"),
                    Place.name_local.ilike(pat, escape="\\"),
                    Place.district.ilike(pat, escape="\\"),
                    Place.division.ilike(pat, escape="\\"),
                    Place.upazila.ilike(pat, escape="\\"),
                )
            )
        if division:
            conditions.append(func.lower(Place.division) == division.strip().lower())
        if district:
            conditions.append(func.lower(Place.district) == district.strip().lower())
        if bbox:
            min_lat, max_lat, min_lng, max_lng = bbox
            conditions.append(
                and_(
                    Place.latitude >= min_lat,
                    Place.latitude <= max_lat,
                    Place.longitude >= min_lng,
                    Place.longitude <= max_lng,
                )
            )
        total = self.db.scalar(select(func.count()).select_from(Place).where(*conditions)) or 0
        stmt = select(Place).where(*conditions)
        if order_by_name:
            stmt = stmt.order_by(Place.name, Place.id)
        if not all_rows:
            stmt = stmt.limit(limit).offset(offset)
        return list(self.db.scalars(stmt)), total

    def content_counts(self, place_ids: list[uuid.UUID]) -> dict[uuid.UUID, tuple[int, int]]:
        """place id -> (post_count, published_story_count)."""
        counts = {pid: [0, 0] for pid in place_ids}
        if not place_ids:
            return {}
        for pid, n in self.db.execute(
            select(Post.place_id, func.count())
            .where(Post.place_id.in_(place_ids))
            .group_by(Post.place_id)
        ):
            counts[pid][0] = n
        for pid, n in self.db.execute(
            select(Story.place_id, func.count())
            .where(Story.place_id.in_(place_ids), Story.status == STATUS_PUBLISHED)
            .group_by(Story.place_id)
        ):
            counts[pid][1] = n
        return {k: (v[0], v[1]) for k, v in counts.items()}

    def popular(self, limit: int) -> list[Place]:
        """Places ordered by amount of content documenting them (then name)."""
        post_n = (
            select(Post.place_id.label("pid"), func.count().label("n"))
            .where(Post.place_id.is_not(None))
            .group_by(Post.place_id)
            .subquery()
        )
        story_n = (
            select(Story.place_id.label("pid"), func.count().label("n"))
            .where(Story.place_id.is_not(None), Story.status == STATUS_PUBLISHED)
            .group_by(Story.place_id)
            .subquery()
        )
        score = func.coalesce(post_n.c.n, 0) + func.coalesce(story_n.c.n, 0)
        stmt = (
            select(Place)
            .outerjoin(post_n, post_n.c.pid == Place.id)
            .outerjoin(story_n, story_n.c.pid == Place.id)
            .order_by(score.desc(), Place.name)
            .limit(limit)
        )
        return list(self.db.scalars(stmt))

    # --- content at a place -----------------------------------------------------------

    def photos(
        self, place_id: uuid.UUID, *, limit: int, before: tuple[datetime, uuid.UUID] | None
    ) -> list[tuple[PostMedia, datetime]]:
        stmt = (
            select(PostMedia, Post.created_at)
            .join(Post, Post.id == PostMedia.post_id)
            .where(Post.place_id == place_id, PostMedia.media_type == "image")
            .order_by(Post.created_at.desc(), PostMedia.id.desc())
            .limit(limit)
        )
        if before is not None:
            stamp, mid = before
            stmt = stmt.where(
                or_(
                    Post.created_at < stamp,
                    and_(Post.created_at == stamp, PostMedia.id < mid),
                )
            )
        return [(m, c) for m, c in self.db.execute(stmt).unique()]

    def documented_by(self, user_id: uuid.UUID, limit: int) -> list[Place]:
        """Places a user has posted or published stories about, most active first."""
        posts = (
            select(Post.place_id.label("pid"), func.count().label("n"))
            .where(Post.author_id == user_id, Post.place_id.is_not(None))
            .group_by(Post.place_id)
        )
        stories = (
            select(Story.place_id.label("pid"), func.count().label("n"))
            .where(
                Story.author_id == user_id,
                Story.place_id.is_not(None),
                Story.status == STATUS_PUBLISHED,
            )
            .group_by(Story.place_id)
        )
        activity = posts.union_all(stories).subquery()
        ranked = (
            select(activity.c.pid)
            .group_by(activity.c.pid)
            .order_by(func.sum(activity.c.n).desc())
            .limit(limit)
        )
        order = [r for r in self.db.scalars(ranked)]
        if not order:
            return []
        found = {p.id: p for p in self.db.scalars(select(Place).where(Place.id.in_(order)))}
        return [found[i] for i in order if i in found]

    def creators(self, place_id: uuid.UUID, limit: int) -> list[User]:
        """People who documented this place, most active first."""
        posts = (
            select(Post.author_id.label("uid"), func.count().label("n"))
            .where(Post.place_id == place_id)
            .group_by(Post.author_id)
        )
        stories = (
            select(Story.author_id.label("uid"), func.count().label("n"))
            .where(Story.place_id == place_id, Story.status == STATUS_PUBLISHED)
            .group_by(Story.author_id)
        )
        activity = posts.union_all(stories).subquery()
        ranked = (
            select(activity.c.uid, func.sum(activity.c.n).label("total"))
            .group_by(activity.c.uid)
            .order_by(func.sum(activity.c.n).desc())
            .limit(limit)
        )
        rows = self.db.execute(ranked).all()
        if not rows:
            return []
        order = [r.uid for r in rows]
        users = {u.id: u for u in self.db.scalars(select(User).where(User.id.in_(order))).unique()}
        return [users[i] for i in order if i in users and users[i].is_active]


__all__ = ["MediaAsset", "PlaceRepository", "like_pattern"]
