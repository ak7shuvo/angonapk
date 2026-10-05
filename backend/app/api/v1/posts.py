import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, Response, status

from app.api.deps import CurrentUser, Posts, Social
from app.core.pagination import InvalidCursorError
from app.schemas.post import FeedPage, PostCreate, PostRead
from app.schemas.social import CommentCreate, CommentPage, CommentRead, LikeState
from app.services.media_service import MediaError
from app.services.post_service import (
    DEFAULT_PAGE_SIZE,
    MAX_PAGE_SIZE,
    NotPostOwnerError,
    PostNotFoundError,
    UnknownPlaceError,
)
from app.services.social_service import PostMissingError

router = APIRouter(prefix="/posts", tags=["posts"])

Limit = Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)]
Cursor = Annotated[str | None, Query(max_length=200)]
NOT_FOUND = HTTPException(status.HTTP_404_NOT_FOUND, "Post not found")


@router.post("", response_model=PostRead, status_code=status.HTTP_201_CREATED)
def create_post(data: PostCreate, user: CurrentUser, posts: Posts) -> PostRead:
    try:
        post = posts.create(user, data)
    except MediaError as exc:
        raise HTTPException(exc.status_code, exc.message) from None
    except UnknownPlaceError:
        raise HTTPException(422, "Unknown place") from None
    return posts.present([post], user)[0]


@router.get("", response_model=FeedPage)
def feed(
    user: CurrentUser,
    posts: Posts,
    limit: Limit = DEFAULT_PAGE_SIZE,
    cursor: Cursor = None,
    scope: Literal["all", "following"] = "all",
    tag: Annotated[str | None, Query(max_length=40)] = None,
) -> FeedPage:
    """Newest-first feed with cursor pagination.

    `scope=all` is the global timeline; `scope=following` shows people you follow
    plus yourself.
    """
    try:
        items, next_cursor = posts.feed(
            limit=limit,
            cursor=cursor,
            following_of=user.id if scope == "following" else None,
            tag=tag.strip().lower().lstrip("#") if tag else None,
        )
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return FeedPage(items=posts.present(items, user), next_cursor=next_cursor)


@router.get("/{post_id}", response_model=PostRead)
def get_post(post_id: uuid.UUID, user: CurrentUser, posts: Posts) -> PostRead:
    try:
        return posts.present([posts.get(post_id)], user)[0]
    except PostNotFoundError:
        raise NOT_FOUND from None


@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_post(post_id: uuid.UUID, user: CurrentUser, posts: Posts) -> Response:
    try:
        posts.delete(user, post_id)
    except PostNotFoundError:
        raise NOT_FOUND from None
    except NotPostOwnerError:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "You can only delete your own posts"
        ) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- likes ---------------------------------------------------------------------


@router.put("/{post_id}/like", response_model=LikeState)
def like_post(post_id: uuid.UUID, user: CurrentUser, social: Social) -> LikeState:
    """Idempotent: liking twice leaves one like."""
    try:
        liked, count, _post, _created = social.like(user, post_id)
    except PostMissingError:
        raise NOT_FOUND from None
    return LikeState(liked=liked, like_count=count)


@router.delete("/{post_id}/like", response_model=LikeState)
def unlike_post(post_id: uuid.UUID, user: CurrentUser, social: Social) -> LikeState:
    try:
        liked, count, _post = social.unlike(user, post_id)
    except PostMissingError:
        raise NOT_FOUND from None
    return LikeState(liked=liked, like_count=count)


# --- saves ---------------------------------------------------------------------


@router.put("/{post_id}/save", status_code=status.HTTP_204_NO_CONTENT)
def save_post(post_id: uuid.UUID, user: CurrentUser, social: Social) -> Response:
    try:
        social.save(user, post_id)
    except PostMissingError:
        raise NOT_FOUND from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{post_id}/save", status_code=status.HTTP_204_NO_CONTENT)
def unsave_post(post_id: uuid.UUID, user: CurrentUser, social: Social) -> Response:
    try:
        social.unsave(user, post_id)
    except PostMissingError:
        raise NOT_FOUND from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- comments ------------------------------------------------------------------


@router.get("/{post_id}/comments", response_model=CommentPage)
def list_comments(
    post_id: uuid.UUID,
    user: CurrentUser,
    social: Social,
    limit: Limit = DEFAULT_PAGE_SIZE,
    cursor: Cursor = None,
) -> CommentPage:
    try:
        items, next_cursor = social.comments(user, post_id, limit=limit, cursor=cursor)
    except PostMissingError:
        raise NOT_FOUND from None
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return CommentPage(items=items, next_cursor=next_cursor)


@router.post("/{post_id}/comments", response_model=CommentRead, status_code=status.HTTP_201_CREATED)
def add_comment(
    post_id: uuid.UUID, data: CommentCreate, user: CurrentUser, social: Social
) -> CommentRead:
    try:
        comment, _post = social.add_comment(user, post_id, data.body)
    except PostMissingError:
        raise NOT_FOUND from None
    return CommentRead.model_validate(comment).model_copy(update={"is_mine": True})
