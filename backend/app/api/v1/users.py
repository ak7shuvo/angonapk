from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status

from app.api.deps import AuthSvc, CurrentUser, Posts, Social, Stories
from app.core.pagination import InvalidCursorError
from app.schemas.post import FeedPage
from app.schemas.profile import ProfileUpdate
from app.schemas.social import FollowState, UserPage
from app.schemas.story import StoryPage
from app.schemas.user import UserRead
from app.services.post_service import DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE
from app.services.social_service import SelfFollowError, UserMissingError

router = APIRouter(prefix="/users", tags=["users"])

Limit = Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)]
Cursor = Annotated[str | None, Query(max_length=200)]
NO_USER = HTTPException(status.HTTP_404_NOT_FOUND, "User not found")


@router.get("/me", response_model=UserRead)
def read_me(user: CurrentUser) -> UserRead:
    return user


@router.patch("/me/profile", response_model=UserRead)
def update_my_profile(data: ProfileUpdate, user: CurrentUser, auth: AuthSvc) -> UserRead:
    return auth.update_profile(user, data)


@router.get("/me/saved/posts", response_model=FeedPage)
def my_saved_posts(
    user: CurrentUser,
    social: Social,
    posts: Posts,
    limit: Limit = DEFAULT_PAGE_SIZE,
    cursor: Cursor = None,
) -> FeedPage:
    """Posts you saved, most recently saved first."""
    try:
        items, next_cursor = social.saved_posts(user, limit=limit, cursor=cursor)
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return FeedPage(items=posts.present(items, user), next_cursor=next_cursor)


@router.get("/me/saved/stories", response_model=StoryPage)
def my_saved_stories(
    user: CurrentUser, stories: Stories, limit: Limit = DEFAULT_PAGE_SIZE, cursor: Cursor = None
) -> StoryPage:
    try:
        items, next_cursor = stories.saved(user, limit=limit, cursor=cursor)
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return StoryPage(items=stories.summaries(items, user), next_cursor=next_cursor)


@router.put("/{username}/follow", response_model=FollowState)
def follow(username: str, user: CurrentUser, social: Social) -> FollowState:
    """Idempotent: following twice leaves one follow."""
    try:
        _target, count, _created = social.follow(user, username)
    except UserMissingError:
        raise NO_USER from None
    except SelfFollowError:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "You cannot follow yourself") from None
    return FollowState(following=True, followers_count=count)


@router.delete("/{username}/follow", response_model=FollowState)
def unfollow(username: str, user: CurrentUser, social: Social) -> FollowState:
    try:
        _target, count = social.unfollow(user, username)
    except UserMissingError:
        raise NO_USER from None
    except SelfFollowError:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "You cannot unfollow yourself") from None
    return FollowState(following=False, followers_count=count)


@router.get("/{username}/followers", response_model=UserPage)
def followers(
    username: str, user: CurrentUser, social: Social, limit: Limit = 30, cursor: Cursor = None
) -> UserPage:
    try:
        items, next_cursor = social.followers(user, username, limit=limit, cursor=cursor)
    except UserMissingError:
        raise NO_USER from None
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return UserPage(items=items, next_cursor=next_cursor)


@router.get("/{username}/following", response_model=UserPage)
def following(
    username: str, user: CurrentUser, social: Social, limit: Limit = 30, cursor: Cursor = None
) -> UserPage:
    try:
        items, next_cursor = social.following(user, username, limit=limit, cursor=cursor)
    except UserMissingError:
        raise NO_USER from None
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return UserPage(items=items, next_cursor=next_cursor)
