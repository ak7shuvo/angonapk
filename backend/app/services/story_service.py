import re
import uuid
from datetime import UTC, datetime

from app.core.pagination import decode_cursor, encode_cursor
from app.core.text import slugify
from app.models import MediaAsset, Story, StoryMedia, User
from app.models.story import STATUS_DRAFT, STATUS_PUBLISHED
from app.repositories.place_repository import PlaceRepository
from app.repositories.story_repository import StoryRepository
from app.repositories.tag_repository import TagRepository
from app.repositories.user_repository import UserRepository
from app.schemas.author import author_dict
from app.schemas.place import PlaceBrief
from app.schemas.story import (
    INLINE_IMAGE_RE,
    CoverRead,
    StoryCreate,
    StoryRead,
    StoryStatus,
    StorySummary,
    StoryUpdate,
)
from app.services.media_service import AssetNotUsableError, MediaService
from app.services.notification_service import NotificationService


class StoryError(Exception):
    status_code = 400

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class StoryNotFoundError(StoryError):
    status_code = 404


class StoryForbiddenError(StoryError):
    status_code = 403


class StoryInvalidError(StoryError):
    status_code = 422


def make_summary(content: str, limit: int = 220) -> str:
    """First readable paragraph, without markup."""
    for block in re.split(r"\n\s*\n", content.strip()):
        block = block.strip()
        if not block or INLINE_IMAGE_RE.fullmatch(block):
            continue
        block = INLINE_IMAGE_RE.sub("", block)
        block = re.sub(r"^(#{1,3}\s+|>\s?)", "", block, flags=re.MULTILINE).strip()
        block = re.sub(r"\s+", " ", block)
        if block:
            return block if len(block) <= limit else block[: limit - 1].rstrip() + "…"
    return ""


def inline_asset_ids(content: str) -> list[uuid.UUID]:
    seen: dict[uuid.UUID, None] = {}
    for _caption, raw in INLINE_IMAGE_RE.findall(content):
        try:
            seen.setdefault(uuid.UUID(raw), None)
        except ValueError as exc:
            raise StoryInvalidError("Invalid image reference in content") from exc
    return list(seen)


def _cover(asset: MediaAsset | None) -> CoverRead | None:
    return CoverRead.model_validate(asset) if asset else None


class StoryService:
    def __init__(
        self,
        repo: StoryRepository,
        tags: TagRepository,
        media: MediaService,
        users: UserRepository,
        places: PlaceRepository,
        notifications: NotificationService,
    ) -> None:
        self.repo = repo
        self.tags = tags
        self.media = media
        self.users = users
        self.places = places
        self.notifications = notifications

    # --- helpers ---------------------------------------------------------------------

    def _ensure_publishable(self, title: str, content: str) -> None:
        if not title.strip() or not content.strip():
            raise StoryInvalidError("A story needs a title and some content to be published")

    def _claim(self, author: User, ids: list[uuid.UUID], mine: frozenset[uuid.UUID]):
        try:
            return self.media.claim(author, ids, allow_attached=mine)
        except AssetNotUsableError as exc:
            raise StoryInvalidError(exc.message) from None

    def _check_place(self, place_id: uuid.UUID | None) -> None:
        if place_id is not None and self.places.get(place_id) is None:
            raise StoryInvalidError("Unknown place")

    def get_visible(self, viewer: User | None, ref: str) -> Story:
        """Published stories are public; drafts are visible only to their author."""
        try:
            story = self.repo.get(uuid.UUID(ref))
        except ValueError:
            story = self.repo.get_by_slug(ref)
        if story is None or not (
            story.is_published or (viewer is not None and story.author_id == viewer.id)
        ):
            raise StoryNotFoundError("Story not found")
        return story

    def _owned(self, user: User, story_id: uuid.UUID) -> Story:
        story = self.repo.get(story_id)
        if story is None or (not story.is_published and story.author_id != user.id):
            raise StoryNotFoundError("Story not found")
        if story.author_id != user.id:
            raise StoryForbiddenError("You can only change your own stories")
        return story

    # --- create / edit ---------------------------------------------------------------

    def create(self, author: User, data: StoryCreate) -> Story:
        publishing = data.status == StoryStatus.PUBLISHED
        self._check_place(data.place_id)
        if publishing:
            self._ensure_publishable(data.title, data.content)
        inline_ids = inline_asset_ids(data.content)
        if data.cover_asset_id and data.cover_asset_id in inline_ids:
            raise StoryInvalidError("The cover image cannot also be used inside the story")
        cover = (
            self._claim(author, [data.cover_asset_id], frozenset()) if data.cover_asset_id else []
        )
        inline = self._claim(author, inline_ids, frozenset())
        now = datetime.now(UTC)
        story = Story(
            author_id=author.id,
            title=data.title,
            slug=self.repo.new_slug(slugify(data.title)),
            content=data.content,
            cover_asset_id=cover[0].id if cover else None,
            location_text=data.location_text,
            place_id=data.place_id,
            tags=self.tags.get_or_create(data.tags),
            status=STATUS_PUBLISHED if publishing else STATUS_DRAFT,
            published_at=now if publishing else None,
            media=[StoryMedia(asset_id=a.id, position=i) for i, a in enumerate(inline)],
        )
        return self.repo.add(story)

    def update(self, user: User, story_id: uuid.UUID, data: StoryUpdate) -> Story:
        story = self._owned(user, story_id)
        fields = data.model_fields_set
        title = data.title if "title" in fields and data.title is not None else story.title
        content = (
            data.content if "content" in fields and data.content is not None else story.content
        )
        if story.is_published:
            self._ensure_publishable(title, content)

        released: list[MediaAsset] = []
        current_inline = {m.asset_id: m for m in story.media}
        desired = inline_asset_ids(content)
        cover_id = data.cover_asset_id if "cover_asset_id" in fields else story.cover_asset_id
        if cover_id and cover_id in desired:
            raise StoryInvalidError("The cover image cannot also be used inside the story")

        mine = frozenset(current_inline) | (
            frozenset([story.cover_asset_id]) if story.cover_asset_id else frozenset()
        )
        new_ids = [i for i in desired if i not in current_inline]
        self._claim(user, new_ids, mine)
        if cover_id != story.cover_asset_id:
            if cover_id:
                self._claim(user, [cover_id], frozenset())
            if story.cover_asset is not None:
                released.append(story.cover_asset)
            story.cover_asset_id = cover_id
        for asset_id, link in list(current_inline.items()):
            if asset_id not in desired:
                released.append(link.asset)
                story.media.remove(link)
        by_id = {a.id: a for a in self.media.repo.get_many(desired).values()}
        for position, asset_id in enumerate(desired):
            link = current_inline.get(asset_id)
            if link is not None:
                link.position = position
            else:
                story.media.append(
                    StoryMedia(asset_id=asset_id, asset=by_id[asset_id], position=position)
                )

        if "title" in fields and data.title is not None:
            story.title = title
        if "content" in fields and data.content is not None:
            story.content = content
        if "location_text" in fields:
            story.location_text = data.location_text
        if "place_id" in fields:
            self._check_place(data.place_id)
            story.place_id = data.place_id
            story.place = self.places.get(data.place_id) if data.place_id else None
        if "tags" in fields and data.tags is not None:
            story.tags = self.tags.get_or_create(data.tags)
        story.updated_at = datetime.now(UTC)
        self.repo.db.flush()
        story.cover_asset = self.media.repo.get(cover_id) if cover_id else None
        saved = self.repo.save(story)
        self.media.release(released)
        return saved

    def publish(self, user: User, story_id: uuid.UUID) -> Story:
        story = self._owned(user, story_id)
        self._ensure_publishable(story.title, story.content)
        if not story.is_published:
            story.status = STATUS_PUBLISHED
            story.published_at = story.published_at or datetime.now(UTC)
            story.updated_at = datetime.now(UTC)
            self.repo.save(story)
        return story

    def unpublish(self, user: User, story_id: uuid.UUID) -> Story:
        story = self._owned(user, story_id)
        if story.is_published:
            story.status = STATUS_DRAFT
            story.updated_at = datetime.now(UTC)
            self.repo.save(story)
        return story

    def delete(self, user: User, story_id: uuid.UUID) -> None:
        story = self._owned(user, story_id)
        assets = [m.asset for m in story.media]
        if story.cover_asset is not None:
            assets.append(story.cover_asset)
        self.repo.delete(story)
        self.notifications.target_deleted("story", story.id)
        self.media.release(assets)

    # --- reading ---------------------------------------------------------------------

    def feed(
        self,
        *,
        limit: int,
        cursor: str | None,
        author: str | None = None,
        tag: str | None = None,
        place_id: uuid.UUID | None = None,
        place_ids: list[uuid.UUID] | None = None,
    ) -> tuple[list[Story], str | None]:
        author_id = None
        if author:
            owner = self.users.get_by_username(author)
            if owner is None:
                return [], None
            author_id = owner.id
        before = decode_cursor(cursor) if cursor else None
        rows = self.repo.published_page(
            limit=limit + 1,
            before=before,
            author_id=author_id,
            tag=tag,
            place_id=place_id,
            place_ids=place_ids,
        )
        page = rows[:limit]
        nxt = encode_cursor(page[-1].published_at, page[-1].id) if len(rows) > limit else None
        return page, nxt

    def mine(
        self, user: User, *, status: str | None, limit: int, cursor: str | None
    ) -> tuple[list[Story], str | None]:
        before = decode_cursor(cursor) if cursor else None
        rows = self.repo.mine_page(user.id, status=status, limit=limit + 1, before=before)
        page = rows[:limit]
        nxt = encode_cursor(page[-1].updated_at, page[-1].id) if len(rows) > limit else None
        return page, nxt

    def related(self, viewer: User | None, ref: str, limit: int = 5) -> list[Story]:
        story = self.get_visible(viewer, ref)
        names = [t.name for t in story.tags]
        scored = []
        for cand in self.repo.related_candidates(story, names):
            shared = len({t.name for t in cand.tags} & set(names))
            score = shared * 2 + (1 if cand.author_id == story.author_id else 0)
            score += 1 if story.place_id and cand.place_id == story.place_id else 0
            scored.append((score, cand.published_at, cand))
        scored.sort(key=lambda t: (t[0], t[1]), reverse=True)
        return [c for _, _, c in scored[:limit]]

    # --- engagement ------------------------------------------------------------------

    def _published(self, story_id: uuid.UUID) -> Story:
        story = self.repo.get(story_id)
        if story is None or not story.is_published:
            raise StoryNotFoundError("Story not found")
        return story

    def like(self, user: User, story_id: uuid.UUID) -> tuple[Story, int, bool]:
        story = self._published(story_id)
        created = self.repo.like(user.id, story.id)
        if created:
            self.notifications.story_liked(user, story)
        return story, self.repo.like_count(story.id), created

    def unlike(self, user: User, story_id: uuid.UUID) -> tuple[Story, int]:
        story = self._published(story_id)
        self.repo.unlike(user.id, story.id)
        self.notifications.like_removed(user, "story", story.id)
        return story, self.repo.like_count(story.id)

    def save(self, user: User, story_id: uuid.UUID) -> None:
        self.repo.save_story(user.id, self._published(story_id).id)

    def unsave(self, user: User, story_id: uuid.UUID) -> None:
        self.repo.unsave_story(user.id, self._published(story_id).id)

    def saved(self, user: User, *, limit: int, cursor: str | None):
        before = decode_cursor(cursor) if cursor else None
        rows = self.repo.saved_page(user.id, limit=limit + 1, before=before)
        page = rows[:limit]
        nxt = encode_cursor(page[-1][1], page[-1][0].id) if len(rows) > limit else None
        return [s for s, _ in page], nxt

    # --- presentation ----------------------------------------------------------------

    def summaries(self, stories: list[Story], viewer: User | None) -> list[StorySummary]:
        stats = self.repo.stats([s.id for s in stories], viewer.id if viewer else None)
        followed = (
            self.repo.followed_authors(viewer.id, list({s.author_id for s in stories}))
            if viewer
            else set()
        )
        return [
            self._summary(s, stats[s.id]).model_copy(
                update={"following_author": s.author_id in followed}
            )
            for s in stories
        ]

    def _summary(self, story: Story, stat: tuple[int, bool, bool]) -> StorySummary:
        likes, liked, saved = stat
        return StorySummary(
            id=story.id,
            slug=story.slug,
            title=story.title,
            summary=make_summary(story.content),
            cover=_cover(story.cover_asset),
            location_text=story.location_text,
            place_id=story.place_id,
            place=PlaceBrief.model_validate(story.place) if story.place else None,
            tags=[t.name for t in story.tags],
            status=StoryStatus(story.status),
            published_at=story.published_at,
            updated_at=story.updated_at,
            reading_minutes=story.reading_minutes,
            author=author_dict(story.author),
            like_count=likes,
            liked_by_me=liked,
            saved_by_me=saved,
        )

    def present(self, story: Story, viewer: User | None) -> StoryRead:
        base = self.summaries([story], viewer)[0]
        return StoryRead(
            **base.model_dump(),
            content=story.content,
            media=[CoverRead.model_validate(m.asset) for m in story.media],
        )
