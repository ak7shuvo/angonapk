from typing import Annotated

from fastapi import APIRouter, Query

from app.api.deps import CurrentUser, Places, Posts, Stories
from app.schemas.map import NearbyRead

router = APIRouter(prefix="/map", tags=["map"])


@router.get("/nearby", response_model=NearbyRead)
def nearby(
    user: CurrentUser,
    places: Places,
    posts: Posts,
    stories: Stories,
    lat: Annotated[float, Query(ge=-90, le=90)],
    lng: Annotated[float, Query(ge=-180, le=180)],
    radius_km: Annotated[float, Query(gt=0, le=200)] = 25,
    limit: Annotated[int, Query(ge=1, le=20)] = 6,
) -> NearbyRead:
    """Places within `radius_km` (nearest first) and the latest posts and stories
    about them. Distances are great-circle distances to the place coordinates."""
    found, _total = places.search(
        q=None,
        division=None,
        district=None,
        bbox=None,
        near=(lat, lng),
        radius_km=radius_km,
        limit=50,
        offset=0,
    )
    ids = [p.id for p in found]
    if not ids:
        return NearbyRead(places=[], posts=[], stories=[])
    nearby_posts, _ = posts.feed(limit=limit, cursor=None, place_ids=ids)
    nearby_stories, _ = stories.feed(limit=limit, cursor=None, place_ids=ids)
    return NearbyRead(
        places=found,
        posts=posts.present(nearby_posts, user),
        stories=stories.summaries(nearby_stories, user),
    )
