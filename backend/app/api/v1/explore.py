from typing import Annotated, Literal

from fastapi import APIRouter, Query

from app.api.deps import CurrentUser, Explorer
from app.schemas.explore import ExploreRead, SearchResults

router = APIRouter(tags=["explore"])


@router.get("/explore", response_model=ExploreRead)
def explore(user: CurrentUser, explorer: Explorer) -> ExploreRead:
    """Home of discovery: categories, trending posts, featured stories, popular places
    and creators. Ranking uses real engagement and activity only."""
    return explorer.explore(user)


@router.get("/search", response_model=SearchResults)
def search(
    user: CurrentUser,
    explorer: Explorer,
    q: Annotated[str, Query(min_length=1, max_length=80)],
    type: Annotated[Literal["all", "users", "stories", "posts", "places"], Query()] = "all",
    limit: Annotated[int, Query(ge=1, le=30)] = 5,
    offset: Annotated[int, Query(ge=0, le=1000)] = 0,
) -> SearchResults:
    """Case-insensitive substring search across people, stories, posts and places.
    With `type=all` each section returns up to `limit` results; a single `type`
    can be paged with `offset`."""
    if not q.strip():
        return SearchResults(query="")
    return explorer.search(user, q, type, limit=limit, offset=offset if type != "all" else 0)
