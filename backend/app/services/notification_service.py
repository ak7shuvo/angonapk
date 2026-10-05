import logging
import uuid

from app.core.pagination import decode_cursor, encode_cursor
from app.models import Notification, User
from app.repositories.notification_repository import NotificationRepository
from app.schemas.notification import NotificationRead

log = logging.getLogger(__name__)

# Notification types produced by V1 features. The column is an open string so
# later features (bookings, community experiences, messages, moderation) add
# their own types without a migration.
LIKE = "like"
COMMENT = "comment"
FOLLOW = "follow"


class NotificationNotFoundError(Exception):
    pass


def _snippet(text: str, limit: int = 120) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


class NotificationService:
    """Creates and serves in-app notifications.

    Producing a notification must never break the action that caused it (a like,
    a comment, a follow), so failures are logged and swallowed.
    """

    def __init__(self, repo: NotificationRepository) -> None:
        self.repo = repo

    # --- producing ----------------------------------------------------------------

    def _create(
        self,
        *,
        recipient: uuid.UUID,
        actor: User | None,
        type: str,
        target_type: str | None,
        target_id: uuid.UUID | None,
        data: dict | None = None,
        dedupe: bool = True,
    ) -> None:
        if actor is not None and actor.id == recipient:
            return  # never notify people about their own actions
        try:
            if dedupe and self.repo.exists(
                recipient_id=recipient,
                actor_id=actor.id if actor else None,
                type=type,
                target_type=target_type,
                target_id=target_id,
            ):
                return
            self.repo.add(
                Notification(
                    recipient_id=recipient,
                    actor_id=actor.id if actor else None,
                    type=type,
                    target_type=target_type,
                    target_id=target_id,
                    data=data or {},
                )
            )
        except Exception:
            self.repo.db.rollback()
            log.exception("could not create %s notification", type)

    def post_liked(self, actor: User, post) -> None:
        self._create(
            recipient=post.author_id,
            actor=actor,
            type=LIKE,
            target_type="post",
            target_id=post.id,
            data={"preview": _snippet(post.body or "")},
        )

    def story_liked(self, actor: User, story) -> None:
        self._create(
            recipient=story.author_id,
            actor=actor,
            type=LIKE,
            target_type="story",
            target_id=story.id,
            data={"preview": story.title, "story_slug": story.slug},
        )

    def commented(self, actor: User, post, comment) -> None:
        self._create(
            recipient=post.author_id,
            actor=actor,
            type=COMMENT,
            target_type="comment",
            target_id=comment.id,
            data={"post_id": str(post.id), "preview": _snippet(comment.body)},
            dedupe=False,
        )

    def followed(self, actor: User, followee_id: uuid.UUID) -> None:
        self._create(
            recipient=followee_id,
            actor=actor,
            type=FOLLOW,
            target_type="user",
            target_id=actor.id,
            data={"username": actor.username},
        )

    # --- retracting (unlike / unfollow / deletes) ----------------------------------

    def retract(self, **filters) -> None:
        try:
            self.repo.delete_matching(**filters)
        except Exception:
            self.repo.db.rollback()
            log.exception("could not remove notifications")

    def like_removed(self, actor: User, target_type: str, target_id: uuid.UUID) -> None:
        self.retract(actor_id=actor.id, type=LIKE, target_type=target_type, target_ids=[target_id])

    def follow_removed(self, actor: User, followee_id: uuid.UUID) -> None:
        self.retract(actor_id=actor.id, type=FOLLOW, recipient_id=followee_id)

    def comment_removed(self, comment_id: uuid.UUID) -> None:
        self.retract(target_type="comment", target_ids=[comment_id])

    def target_deleted(self, target_type: str, target_id: uuid.UUID, comment_ids=()) -> None:
        self.retract(target_type=target_type, target_ids=[target_id])
        if comment_ids:
            self.retract(target_type="comment", target_ids=list(comment_ids))

    # --- reading --------------------------------------------------------------------

    def list(
        self, user: User, *, limit: int, cursor: str | None, unread_only: bool
    ) -> tuple[list[NotificationRead], str | None]:
        before = decode_cursor(cursor) if cursor else None
        rows = self.repo.page(user.id, limit=limit + 1, before=before, unread_only=unread_only)
        page = rows[:limit]
        nxt = encode_cursor(page[-1].created_at, page[-1].id) if len(rows) > limit else None
        return [self.present(n) for n in page], nxt

    @staticmethod
    def present(n: Notification) -> NotificationRead:
        return NotificationRead.model_validate(n)

    def unread_count(self, user: User) -> int:
        return self.repo.unread_count(user.id)

    def mark_read(self, user: User, notification_id: uuid.UUID) -> NotificationRead:
        n = self.repo.get_owned(notification_id, user.id)
        if n is None:
            raise NotificationNotFoundError
        return self.present(self.repo.mark_read(n))

    def mark_all_read(self, user: User) -> int:
        return self.repo.mark_all_read(user.id)
