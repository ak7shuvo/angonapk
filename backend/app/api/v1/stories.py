import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, Response, status

from app.api.deps import CurrentUser, Stories
from app.core.pagination import InvalidCursorError
from app.core.rate_limit import limit_by_user
from app.schemas.social import LikeState
from app.schemas.story import StoryCreate, StoryPage, StoryRead, StorySummary, StoryUpdate
from app.services.story_service import StoryError

router = APIRouter(prefix="/stories", tags=["stories"])


Limit = Annotated[int, Query(ge=1, le=50)]
Cursor = Annotated[str | None, Query(max_length=200)]


def _http(exc: StoryError) -> HTTPException:
    return HTTPException(exc.status_code, exc.message)


@router.post(
    "",
    response_model=StoryRead,
    status_code=status.HTTP_201_CREATED,
    dependencies=[limit_by_user("story", 20, 3600)],
)
def create_story(data: StoryCreate, user: CurrentUser, stories: Stories) -> StoryRead:
    try:
        return stories.present(stories.create(user, data), user)
    except StoryError as exc:
        raise _http(exc) from None


@router.get("", response_model=StoryPage)
def story_feed(
    user: CurrentUser,
    stories: Stories,
    limit: Limit = 20,
    cursor: Cursor = None,
    author: Annotated[str | None, Query(max_length=30)] = None,
    tag: Annotated[str | None, Query(max_length=40)] = None,
) -> StoryPage:
    """Published stories, newest first."""
    try:
        items, nxt = stories.feed(limit=limit, cursor=cursor, author=author, tag=tag)
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return StoryPage(items=stories.summaries(items, user), next_cursor=nxt)


@router.get("/mine", response_model=StoryPage)
def my_stories(
    user: CurrentUser,
    stories: Stories,
    limit: Limit = 20,
    cursor: Cursor = None,
    status_filter: Annotated[Literal["draft", "published", "all"], Query(alias="status")] = "all",
) -> StoryPage:
    """Your own stories including drafts, most recently edited first."""
    try:
        items, nxt = stories.mine(
            user,
            status=None if status_filter == "all" else status_filter,
            limit=limit,
            cursor=cursor,
        )
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return StoryPage(items=stories.summaries(items, user), next_cursor=nxt)


@router.get("/{ref}", response_model=StoryRead)
def get_story(ref: str, user: CurrentUser, stories: Stories) -> StoryRead:
    """By id or slug. Drafts are visible only to their author."""
    try:
        return stories.present(stories.get_visible(user, ref), user)
    except StoryError as exc:
        raise _http(exc) from None


@router.get("/{ref}/related", response_model=list[StorySummary])
def related_stories(
    ref: str, user: CurrentUser, stories: Stories, limit: Annotated[int, Query(ge=1, le=20)] = 5
) -> list[StorySummary]:
    try:
        return stories.summaries(stories.related(user, ref, limit), user)
    except StoryError as exc:
        raise _http(exc) from None


@router.patch("/{story_id}", response_model=StoryRead)
def update_story(
    story_id: uuid.UUID, data: StoryUpdate, user: CurrentUser, stories: Stories
) -> StoryRead:
    try:
        return stories.present(stories.update(user, story_id, data), user)
    except StoryError as exc:
        raise _http(exc) from None


@router.post("/{story_id}/publish", response_model=StoryRead)
def publish_story(story_id: uuid.UUID, user: CurrentUser, stories: Stories) -> StoryRead:
    try:
        return stories.present(stories.publish(user, story_id), user)
    except StoryError as exc:
        raise _http(exc) from None


@router.post("/{story_id}/unpublish", response_model=StoryRead)
def unpublish_story(story_id: uuid.UUID, user: CurrentUser, stories: Stories) -> StoryRead:
    try:
        return stories.present(stories.unpublish(user, story_id), user)
    except StoryError as exc:
        raise _http(exc) from None


@router.delete("/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_story(story_id: uuid.UUID, user: CurrentUser, stories: Stories) -> Response:
    try:
        stories.delete(user, story_id)
    except StoryError as exc:
        raise _http(exc) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/{story_id}/like", response_model=LikeState)
def like_story(story_id: uuid.UUID, user: CurrentUser, stories: Stories) -> LikeState:
    try:
        _story, count, _created = stories.like(user, story_id)
    except StoryError as exc:
        raise _http(exc) from None
    return LikeState(liked=True, like_count=count)


@router.delete("/{story_id}/like", response_model=LikeState)
def unlike_story(story_id: uuid.UUID, user: CurrentUser, stories: Stories) -> LikeState:
    try:
        _story, count = stories.unlike(user, story_id)
    except StoryError as exc:
        raise _http(exc) from None
    return LikeState(liked=False, like_count=count)


@router.put("/{story_id}/save", status_code=status.HTTP_204_NO_CONTENT)
def save_story(story_id: uuid.UUID, user: CurrentUser, stories: Stories) -> Response:
    try:
        stories.save(user, story_id)
    except StoryError as exc:
        raise _http(exc) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{story_id}/save", status_code=status.HTTP_204_NO_CONTENT)
def unsave_story(story_id: uuid.UUID, user: CurrentUser, stories: Stories) -> Response:
    try:
        stories.unsave(user, story_id)
    except StoryError as exc:
        raise _http(exc) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)
