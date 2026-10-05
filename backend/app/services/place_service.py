import uuid
from typing import Any

from app.core.geo import bounding_box, haversine_km
from app.core.pagination import decode_cursor, encode_cursor
from app.core.text import slugify
from app.models import Place, User
from app.repositories.place_repository import PlaceRepository
from app.repositories.social_repository import SocialRepository
from app.schemas.place import (
    PhotoPage,
    PhotoRead,
    PlaceCreate,
    PlaceRead,
    PlaceSummary,
    PlaceUpdate,
)
from app.schemas.social import UserSummary
from app.services.social_service import user_summary


class PlaceError(Exception):
    status_code = 400

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class PlaceNotFoundError(PlaceError):
    status_code = 404


class PlaceService:
    def __init__(self, places: PlaceRepository, social: SocialRepository) -> None:
        self.places = places
        self.social = social

    def by_slug(self, slug: str) -> Place:
        place = self.places.get_by_slug(slug.strip().lower())
        if place is None:
            raise PlaceNotFoundError("Place not found")
        return place

    # --- presentation ----------------------------------------------------------------

    def summaries(
        self, places: list[Place], *, origin: tuple[float, float] | None = None
    ) -> list[PlaceSummary]:
        counts = self.places.content_counts([p.id for p in places])
        out = []
        for p in places:
            posts, stories = counts.get(p.id, (0, 0))
            summary = PlaceSummary.model_validate(p).model_copy(
                update={
                    "post_count": posts,
                    "story_count": stories,
                    "distance_km": round(haversine_km(*origin, p.latitude, p.longitude), 2)
                    if origin
                    else None,
                }
            )
            out.append(summary)
        return out

    def present(self, place: Place) -> PlaceRead:
        posts, stories = self.places.content_counts([place.id]).get(place.id, (0, 0))
        return PlaceRead.model_validate(place).model_copy(
            update={"post_count": posts, "story_count": stories}
        )

    # --- discovery ---------------------------------------------------------------------

    def search(
        self,
        *,
        q: str | None,
        division: str | None,
        district: str | None,
        bbox: tuple[float, float, float, float] | None,
        near: tuple[float, float] | None,
        radius_km: float,
        limit: int,
        offset: int,
    ) -> tuple[list[PlaceSummary], int]:
        if near is not None:
            box = bounding_box(near[0], near[1], radius_km)
            rows, _ = self.places.search(
                q=q, division=division, district=district, bbox=box, all_rows=True
            )
            within = [(haversine_km(near[0], near[1], p.latitude, p.longitude), p) for p in rows]
            within = sorted(
                [(d, p) for d, p in within if d <= radius_km], key=lambda t: (t[0], t[1].name)
            )
            page = [p for _, p in within[offset : offset + limit]]
            return self.summaries(page, origin=near), len(within)
        rows, total = self.places.search(
            q=q, division=division, district=district, bbox=bbox, limit=limit, offset=offset
        )
        return self.summaries(rows), total

    def popular(self, limit: int) -> list[PlaceSummary]:
        return self.summaries(self.places.popular(limit))

    # --- content at a place -----------------------------------------------------------

    def photos(self, place: Place, *, limit: int, cursor: str | None) -> PhotoPage:
        before = decode_cursor(cursor) if cursor else None
        rows = self.places.photos(place.id, limit=limit + 1, before=before)
        page = rows[:limit]
        nxt = encode_cursor(page[-1][1], page[-1][0].id) if len(rows) > limit else None
        return PhotoPage(
            items=[
                PhotoRead(id=m.id, url=m.url, width=m.width, height=m.height, post_id=m.post_id)
                for m, _ in page
            ],
            next_cursor=nxt,
        )

    def documented_by(self, user: User, limit: int = 50) -> list[PlaceSummary]:
        return self.summaries(self.places.documented_by(user.id, limit))

    def creators(self, viewer: User, place: Place, limit: int) -> list[UserSummary]:
        users = self.places.creators(place.id, limit)
        followed = self.social.following_ids(viewer.id, [u.id for u in users])
        return [
            user_summary(u, is_following=u.id in followed, is_me=u.id == viewer.id) for u in users
        ]

    # --- admin ------------------------------------------------------------------------

    def create(self, data: PlaceCreate) -> Place:
        slug = self._unique_slug(slugify(data.name))
        place = Place(
            name=data.name,
            name_local=data.name_local,
            slug=slug,
            description=data.description,
            cover_url=data.cover_url,
            latitude=data.latitude,
            longitude=data.longitude,
            country=data.country,
            division=data.division,
            district=data.district,
            upazila=data.upazila,
            meta=data.metadata,
        )
        return self.places.add(place)

    def update(self, place_id: uuid.UUID, data: PlaceUpdate) -> Place:
        place = self.places.get(place_id)
        if place is None:
            raise PlaceNotFoundError("Place not found")
        fields: dict[str, Any] = data.model_dump(exclude_unset=True)
        if "metadata" in fields:
            place.meta = fields.pop("metadata") or {}
        for name, value in fields.items():
            if name in {"name", "latitude", "longitude"} and value is None:
                continue  # required columns cannot be cleared
            setattr(place, name, value)
        return self.places.save(place)

    def _unique_slug(self, base: str) -> str:
        slug, n = base, 2
        while self.places.slug_exists(slug):
            slug = f"{base}-{n}"
            n += 1
        return slug
