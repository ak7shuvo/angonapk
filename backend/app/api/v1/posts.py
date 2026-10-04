import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status

from app.api.deps import CurrentUser, DbSession
from app.repositories.post_repository import PostRepository
from app.schemas.post import FeedPage, PostCreate, PostRead
from app.services.post_service import (
    DEFAULT_PAGE_SIZE,
    MAX_PAGE_SIZE,
    InvalidCursorError,
    NotPostOwnerError,
    PostNotFoundError,
    PostService,
)

router = APIRouter(prefix="/posts", tags=["posts"])


def get_post_service(db: DbSession) -> PostService:
    return PostService(PostRepository(db))


Posts = Annotated[PostService, Depends(get_post_service)]


@router.post("", response_model=PostRead, status_code=status.HTTP_201_CREATED)
def create_post(data: PostCreate, user: CurrentUser, posts: Posts) -> PostRead:
    return posts.create(user, data)


@router.get("", response_model=FeedPage)
def feed(
    _user: CurrentUser,
    posts: Posts,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
    cursor: Annotated[str | None, Query(max_length=200)] = None,
) -> FeedPage:
    """Newest-first feed with cursor pagination.

    Until follows exist (Phase 05) this is the global timeline.
    """
    try:
        items, next_cursor = posts.feed(limit=limit, cursor=cursor)
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return FeedPage(items=items, next_cursor=next_cursor)


@router.get("/{post_id}", response_model=PostRead)
def get_post(post_id: uuid.UUID, _user: CurrentUser, posts: Posts) -> PostRead:
    try:
        return posts.get(post_id)
    except PostNotFoundError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Post not found") from None


@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_post(post_id: uuid.UUID, user: CurrentUser, posts: Posts) -> Response:
    try:
        posts.delete(user, post_id)
    except PostNotFoundError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Post not found") from None
    except NotPostOwnerError:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "You can only delete your own posts"
        ) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)
