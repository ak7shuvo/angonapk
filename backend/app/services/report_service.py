import uuid
from datetime import UTC, datetime, timedelta

from app.core.pagination import decode_cursor, encode_cursor
from app.models import Report, User
from app.models.report import STATUS_DISMISSED, STATUS_OPEN, STATUS_RESOLVED
from app.repositories.post_repository import PostRepository
from app.repositories.report_repository import DuplicateReportError, ReportRepository
from app.repositories.social_repository import SocialRepository
from app.repositories.story_repository import StoryRepository
from app.repositories.user_repository import UserRepository
from app.schemas.author import author_dict
from app.schemas.report import ReportAdminRead, ReportCreate, ReportUpdate
from app.services.notification_service import NotificationService

# A person can file at most this many reports per rolling day: enough for real
# use, too few to flood the moderation queue.
DAILY_REPORT_LIMIT = 20
MODERATION = "moderation"


class ReportTargetNotFoundError(Exception):
    pass


class SelfReportError(Exception):
    pass


class AlreadyReportedError(Exception):
    pass


class ReportLimitError(Exception):
    pass


class ReportNotFoundError(Exception):
    pass


def _snippet(text: str | None, limit: int = 200) -> str | None:
    if not text:
        return None
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


class ReportService:
    def __init__(
        self,
        repo: ReportRepository,
        posts: PostRepository,
        stories: StoryRepository,
        users: UserRepository,
        social: SocialRepository,
        notifier: NotificationService,
    ) -> None:
        self.repo = repo
        self.posts = posts
        self.stories = stories
        self.users = users
        self.social = social
        self.notifier = notifier

    # --- target lookup -------------------------------------------------------------

    def _resolve(
        self, target_type: str, target_id: uuid.UUID
    ) -> tuple[User | None, str | None] | None:
        """(author, preview) for something that exists and is publicly visible, else None."""
        if target_type == "post":
            post = self.posts.get(target_id)
            return None if post is None else (post.author, _snippet(post.body))
        if target_type == "story":
            story = self.stories.get(target_id)
            if story is None or not story.is_published:
                return None
            return story.author, _snippet(story.title)
        if target_type == "comment":
            comment = self.social.get_comment(target_id)
            return None if comment is None else (comment.author, _snippet(comment.body))
        user = self.users.get(target_id)
        return None if user is None else (user, f"@{user.username}")

    # --- reporting -----------------------------------------------------------------

    def report(self, reporter: User, data: ReportCreate) -> Report:
        found = self._resolve(data.target_type, data.target_id)
        if found is None:
            raise ReportTargetNotFoundError
        author, _ = found
        if author is not None and author.id == reporter.id:
            raise SelfReportError
        if self.repo.exists(reporter.id, data.target_type, data.target_id):
            raise AlreadyReportedError
        if self.repo.count_since(reporter.id, timedelta(days=1)) >= DAILY_REPORT_LIMIT:
            raise ReportLimitError
        try:
            return self.repo.add(
                Report(
                    reporter_id=reporter.id,
                    target_type=data.target_type,
                    target_id=data.target_id,
                    reason=data.reason,
                    details=data.details,
                )
            )
        except DuplicateReportError:
            raise AlreadyReportedError from None

    # --- moderation (admin) --------------------------------------------------------

    def _present(self, rows: list[Report]) -> list[ReportAdminRead]:
        counts = self.repo.target_counts({(r.target_type, r.target_id) for r in rows})
        out = []
        for r in rows:
            item = ReportAdminRead.model_validate(r)
            found = self._resolve(r.target_type, r.target_id)
            if found is None:
                item.target = {"exists": False, "author": None, "preview": None}
            else:
                author, preview = found
                item.target = {
                    "exists": True,
                    "author": author_dict(author) if author else None,
                    "preview": preview,
                }
            item.report_count_for_target = counts.get((r.target_type, r.target_id), 1)
            out.append(item)
        return out

    def list(
        self, *, limit: int, cursor: str | None, status: str | None, target_type: str | None
    ) -> tuple[list[ReportAdminRead], str | None]:
        before = decode_cursor(cursor) if cursor else None
        rows = self.repo.page(
            limit=limit + 1, before=before, status=status, target_type=target_type
        )
        page = rows[:limit]
        nxt = encode_cursor(page[-1].created_at, page[-1].id) if len(rows) > limit else None
        return self._present(page), nxt

    def get(self, report_id: uuid.UUID) -> ReportAdminRead:
        report = self.repo.get(report_id)
        if report is None:
            raise ReportNotFoundError
        return self._present([report])[0]

    def update(self, admin: User, report_id: uuid.UUID, data: ReportUpdate) -> ReportAdminRead:
        report = self.repo.get(report_id)
        if report is None:
            raise ReportNotFoundError
        was_open = report.status in (STATUS_OPEN, "reviewing")
        report.status = data.status
        report.resolution_note = data.resolution_note
        report.reviewed_by_id = admin.id
        report.reviewed_at = datetime.now(UTC)
        self.repo.save(report)
        if was_open and data.status in (STATUS_RESOLVED, STATUS_DISMISSED):
            self.notifier.system(
                report.reporter_id,
                type=MODERATION,
                target_type=report.target_type,
                target_id=report.target_id,
                data={
                    "title": "Thanks for your report",
                    "body": "We reviewed it and took action."
                    if data.status == STATUS_RESOLVED
                    else "We reviewed it and found no violation of our guidelines.",
                },
            )
        return self._present([report])[0]
