import uuid
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status

from app.api.deps import CurrentUser, Notifier
from app.core.pagination import InvalidCursorError
from app.schemas.notification import NotificationPage, NotificationRead, UnreadCount
from app.services.notification_service import NotificationNotFoundError

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=NotificationPage)
def list_notifications(
    user: CurrentUser,
    notifier: Notifier,
    limit: Annotated[int, Query(ge=1, le=50)] = 30,
    cursor: Annotated[str | None, Query(max_length=200)] = None,
    unread_only: bool = False,
) -> NotificationPage:
    """Your notifications, newest first."""
    try:
        items, nxt = notifier.list(user, limit=limit, cursor=cursor, unread_only=unread_only)
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return NotificationPage(items=items, next_cursor=nxt)


@router.get("/unread-count", response_model=UnreadCount)
def unread_count(user: CurrentUser, notifier: Notifier) -> UnreadCount:
    return UnreadCount(unread=notifier.unread_count(user))


@router.post("/read-all", response_model=UnreadCount)
def mark_all_read(user: CurrentUser, notifier: Notifier) -> UnreadCount:
    notifier.mark_all_read(user)
    return UnreadCount(unread=0)


@router.post("/{notification_id}/read", response_model=NotificationRead)
def mark_read(
    notification_id: uuid.UUID, user: CurrentUser, notifier: Notifier
) -> NotificationRead:
    """Marks one of *your* notifications as read (idempotent)."""
    try:
        return notifier.mark_read(user, notification_id)
    except NotificationNotFoundError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Notification not found") from None
