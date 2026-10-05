import uuid
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status

from app.api.deps import AdminUser, CurrentUser, Places, Posts, Stories
from app.core.pagination import InvalidCursorError
from app.schemas.place import (
    PhotoPage,
    PlaceCreate,
    PlaceList,
    PlaceRead,
    PlaceSummary,
    PlaceUpdate,
)
from app.schemas.post import FeedPage
from app.schemas.social import UserSummary
from app.schemas.story import StoryPage
from app.services.place_service import PlaceError

router = APIRouter(prefix="/places", tags=["places"])

Cursor = Annotated[str | None, Query(max_length=200)]
PageLimit = Annotated[int, Query(ge=1, le=50)]


def _http(exc: PlaceError) -> HTTPException:
    return HTTPException(exc.status_code, exc.message)


@router.get("", response_model=PlaceList)
def list_places(
    _user: CurrentUser,
    places: Places,
    q: Annotated[str | None, Query(max_length=80)] = None,
    division: Annotated[str | None, Query(max_length=80)] = None,
    district: Annotated[str | None, Query(max_length=80)] = None,
    min_lat: Annotated[float | None, Query(ge=-90, le=90)] = None,
    max_lat: Annotated[float | None, Query(ge=-90, le=90)] = None,
    min_lng: Annotated[float | None, Query(ge=-180, le=180)] = None,
    max_lng: Annotated[float | None, Query(ge=-180, le=180)] = None,
    near_lat: Annotated[float | None, Query(ge=-90, le=90)] = None,
    near_lng: Annotated[float | None, Query(ge=-180, le=180)] = None,
    radius_km: Annotated[float, Query(gt=0, le=500)] = 50,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0, le=10_000)] = 0,
) -> PlaceList:
    """Search and filter places. `near_lat`+`near_lng` sorts by distance and returns
    `distance_km`; the four bounding-box parameters (map viewport) must come together."""
    bbox_parts = [min_lat, max_lat, min_lng, max_lng]
    if any(p is not None for p in bbox_parts) and not all(p is not None for p in bbox_parts):
        raise HTTPException(422, "min_lat, max_lat, min_lng and max_lng must be given together")
    if (near_lat is None) != (near_lng is None):
        raise HTTPException(422, "near_lat and near_lng must be given together")
    bbox = (min_lat, max_lat, min_lng, max_lng) if min_lat is not None else None  # type: ignore[assignment]
    items, total = places.search(
        q=q,
        division=division,
        district=district,
        bbox=bbox,
        near=(near_lat, near_lng) if near_lat is not None else None,  # type: ignore[arg-type]
        radius_km=radius_km,
        limit=limit,
        offset=offset,
    )
    return PlaceList(items=items, total=total)


@router.post("", response_model=PlaceRead, status_code=status.HTTP_201_CREATED)
def create_place(data: PlaceCreate, _admin: AdminUser, places: Places) -> PlaceRead:
    """Admin only. Places are curated, not user-generated."""
    return places.present(places.create(data))


@router.patch("/{place_id}", response_model=PlaceRead)
def update_place(
    place_id: uuid.UUID, data: PlaceUpdate, _admin: AdminUser, places: Places
) -> PlaceRead:
    try:
        return places.present(places.update(place_id, data))
    except PlaceError as exc:
        raise _http(exc) from None


@router.get("/{slug}", response_model=PlaceRead)
def get_place(slug: str, _user: CurrentUser, places: Places) -> PlaceRead:
    try:
        return places.present(places.by_slug(slug))
    except PlaceError as exc:
        raise _http(exc) from None


@router.get("/{slug}/posts", response_model=FeedPage)
def place_posts(
    slug: str,
    user: CurrentUser,
    places: Places,
    posts: Posts,
    limit: PageLimit = 20,
    cursor: Cursor = None,
) -> FeedPage:
    try:
        place = places.by_slug(slug)
        items, nxt = posts.feed(limit=limit, cursor=cursor, place_id=place.id)
    except PlaceError as exc:
        raise _http(exc) from None
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return FeedPage(items=posts.present(items, user), next_cursor=nxt)


@router.get("/{slug}/stories", response_model=StoryPage)
def place_stories(
    slug: str,
    user: CurrentUser,
    places: Places,
    stories: Stories,
    limit: PageLimit = 20,
    cursor: Cursor = None,
) -> StoryPage:
    try:
        place = places.by_slug(slug)
        items, nxt = stories.feed(limit=limit, cursor=cursor, place_id=place.id)
    except PlaceError as exc:
        raise _http(exc) from None
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return StoryPage(items=stories.summaries(items, user), next_cursor=nxt)


@router.get("/{slug}/photos", response_model=PhotoPage)
def place_photos(
    slug: str, _user: CurrentUser, places: Places, limit: PageLimit = 30, cursor: Cursor = None
) -> PhotoPage:
    try:
        return places.photos(places.by_slug(slug), limit=limit, cursor=cursor)
    except PlaceError as exc:
        raise _http(exc) from None
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None


@router.get("/{slug}/creators", response_model=list[UserSummary])
def place_creators(
    slug: str,
    user: CurrentUser,
    places: Places,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> list[UserSummary]:
    """People who have posted or published stories about this place."""
    try:
        return places.creators(user, places.by_slug(slug), limit)
    except PlaceError as exc:
        raise _http(exc) from None


__all__ = ["PlaceSummary", "router"]
