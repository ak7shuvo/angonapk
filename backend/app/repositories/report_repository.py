import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import Report


class DuplicateReportError(Exception):
    pass


class ReportRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def add(self, report: Report) -> Report:
        self.db.add(report)
        try:
            self.db.commit()
        except IntegrityError:  # lost a race with an identical report
            self.db.rollback()
            raise DuplicateReportError from None
        return report

    def exists(self, reporter_id: uuid.UUID, target_type: str, target_id: uuid.UUID) -> bool:
        return (
            self.db.scalar(
                select(Report.id).where(
                    Report.reporter_id == reporter_id,
                    Report.target_type == target_type,
                    Report.target_id == target_id,
                )
            )
            is not None
        )

    def count_since(self, reporter_id: uuid.UUID, since: timedelta) -> int:
        cutoff = datetime.now(UTC) - since
        return (
            self.db.scalar(
                select(func.count()).where(
                    Report.reporter_id == reporter_id, Report.created_at >= cutoff
                )
            )
            or 0
        )

    def get(self, report_id: uuid.UUID) -> Report | None:
        return self.db.get(Report, report_id)

    def page(
        self,
        *,
        limit: int,
        before: tuple[datetime, uuid.UUID] | None,
        status: str | None,
        target_type: str | None,
    ) -> list[Report]:
        stmt = select(Report).order_by(Report.created_at.desc(), Report.id.desc()).limit(limit)
        if status:
            stmt = stmt.where(Report.status == status)
        if target_type:
            stmt = stmt.where(Report.target_type == target_type)
        if before is not None:
            stamp, rid = before
            stmt = stmt.where(
                or_(Report.created_at < stamp, and_(Report.created_at == stamp, Report.id < rid))
            )
        return list(self.db.scalars(stmt).unique())

    def save(self, report: Report) -> Report:
        self.db.commit()
        return report

    def target_counts(
        self, targets: set[tuple[str, uuid.UUID]]
    ) -> dict[tuple[str, uuid.UUID], int]:
        """How many reports each (target_type, target_id) has received."""
        if not targets:
            return {}
        rows = self.db.execute(
            select(Report.target_type, Report.target_id, func.count())
            .where(or_(*[and_(Report.target_type == t, Report.target_id == i) for t, i in targets]))
            .group_by(Report.target_type, Report.target_id)
        )
        return {(t, i): n for t, i, n in rows}
