import uuid
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status

from app.api.deps import AdminUser, CurrentUser, Reports
from app.core.pagination import InvalidCursorError
from app.core.rate_limit import limit_by_user
from app.models.report import STATUSES, TARGET_TYPES
from app.schemas.report import (
    ReportAdminPage,
    ReportAdminRead,
    ReportCreate,
    ReportReceipt,
    ReportUpdate,
)
from app.services.report_service import (
    AlreadyReportedError,
    ReportLimitError,
    ReportNotFoundError,
    ReportTargetNotFoundError,
    SelfReportError,
)

router = APIRouter(tags=["moderation"])


@router.post(
    "/reports",
    response_model=ReportReceipt,
    status_code=status.HTTP_201_CREATED,
    dependencies=[limit_by_user("report", 10, 600)],
)
def create_report(data: ReportCreate, user: CurrentUser, reports: Reports) -> ReportReceipt:
    """Report a post, story, comment or profile for review by moderators."""
    try:
        return ReportReceipt.model_validate(reports.report(user, data))
    except ReportTargetNotFoundError:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "That content is no longer available"
        ) from None
    except SelfReportError:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "You can't report your own content"
        ) from None
    except AlreadyReportedError:
        raise HTTPException(status.HTTP_409_CONFLICT, "You have already reported this") from None
    except ReportLimitError:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "You've sent a lot of reports today. Try again tomorrow.",
        ) from None


# --- admin -------------------------------------------------------------------------


@router.get("/admin/reports", response_model=ReportAdminPage)
def list_reports(
    _: AdminUser,
    reports: Reports,
    status_filter: Annotated[
        str | None, Query(alias="status", pattern=f"^({'|'.join(STATUSES)})$")
    ] = None,
    target_type: Annotated[str | None, Query(pattern=f"^({'|'.join(TARGET_TYPES)})$")] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
    cursor: Annotated[str | None, Query(max_length=200)] = None,
) -> ReportAdminPage:
    """The moderation queue, newest first."""
    try:
        items, nxt = reports.list(
            limit=limit, cursor=cursor, status=status_filter, target_type=target_type
        )
    except InvalidCursorError:
        raise HTTPException(422, "Invalid cursor") from None
    return ReportAdminPage(items=items, next_cursor=nxt)


@router.get("/admin/reports/{report_id}", response_model=ReportAdminRead)
def get_report(report_id: uuid.UUID, _: AdminUser, reports: Reports) -> ReportAdminRead:
    try:
        return reports.get(report_id)
    except ReportNotFoundError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Report not found") from None


@router.patch("/admin/reports/{report_id}", response_model=ReportAdminRead)
def update_report(
    report_id: uuid.UUID, data: ReportUpdate, admin: AdminUser, reports: Reports
) -> ReportAdminRead:
    """Move a report through open → reviewing → resolved / dismissed."""
    try:
        return reports.update(admin, report_id, data)
    except ReportNotFoundError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Report not found") from None
