import uuid
from datetime import UTC, datetime

from sqlalchemy import and_, delete, func, or_, select, update
from sqlalchemy.orm import Session

from app.models import Notification


class NotificationRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def add(self, n: Notification) -> Notification:
        self.db.add(n)
        self.db.commit()
        return n

    def exists(
        self,
        *,
        recipient_id: uuid.UUID,
        actor_id: uuid.UUID | None,
        type: str,
        target_type: str | None,
        target_id: uuid.UUID | None,
    ) -> bool:
        stmt = select(Notification.id).where(
            Notification.recipient_id == recipient_id,
            Notification.actor_id == actor_id,
            Notification.type == type,
            Notification.target_type == target_type,
            Notification.target_id == target_id,
        )
        return self.db.scalar(stmt.limit(1)) is not None

    def delete_matching(
        self,
        *,
        actor_id: uuid.UUID | None = None,
        type: str | None = None,
        target_type: str | None = None,
        target_ids: list[uuid.UUID] | None = None,
        recipient_id: uuid.UUID | None = None,
    ) -> None:
        conditions = []
        if actor_id is not None:
            conditions.append(Notification.actor_id == actor_id)
        if type is not None:
            conditions.append(Notification.type == type)
        if target_type is not None:
            conditions.append(Notification.target_type == target_type)
        if target_ids is not None:
            conditions.append(Notification.target_id.in_(target_ids))
        if recipient_id is not None:
            conditions.append(Notification.recipient_id == recipient_id)
        if not conditions:
            raise ValueError("refusing to delete every notification")
        self.db.execute(delete(Notification).where(*conditions))
        self.db.commit()

    def page(
        self,
        recipient_id: uuid.UUID,
        *,
        limit: int,
        before: tuple[datetime, uuid.UUID] | None,
        unread_only: bool,
    ) -> list[Notification]:
        stmt = (
            select(Notification)
            .where(Notification.recipient_id == recipient_id)
            .order_by(Notification.created_at.desc(), Notification.id.desc())
            .limit(limit)
        )
        if unread_only:
            stmt = stmt.where(Notification.read_at.is_(None))
        if before is not None:
            stamp, nid = before
            stmt = stmt.where(
                or_(
                    Notification.created_at < stamp,
                    and_(Notification.created_at == stamp, Notification.id < nid),
                )
            )
        return list(self.db.scalars(stmt).unique())

    def unread_count(self, recipient_id: uuid.UUID) -> int:
        return (
            self.db.scalar(
                select(func.count()).where(
                    Notification.recipient_id == recipient_id, Notification.read_at.is_(None)
                )
            )
            or 0
        )

    def get_owned(self, notification_id: uuid.UUID, recipient_id: uuid.UUID) -> Notification | None:
        return self.db.scalar(
            select(Notification).where(
                Notification.id == notification_id, Notification.recipient_id == recipient_id
            )
        )

    def mark_read(self, n: Notification) -> Notification:
        if n.read_at is None:
            n.read_at = datetime.now(UTC)
            self.db.commit()
        return n

    def mark_all_read(self, recipient_id: uuid.UUID) -> int:
        res = self.db.execute(
            update(Notification)
            .where(Notification.recipient_id == recipient_id, Notification.read_at.is_(None))
            .values(read_at=datetime.now(UTC))
        )
        self.db.commit()
        return res.rowcount
