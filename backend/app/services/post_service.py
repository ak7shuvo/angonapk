import base64
import binascii
import uuid
from datetime import datetime

from app.models import Post, User
from app.repositories.post_repository import PostRepository
from app.repositories.tag_repository import TagRepository
from app.schemas.post import PostCreate
from app.services.media_service import MediaService

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 50


class PostNotFoundError(Exception):
    pass


class NotPostOwnerError(Exception):
    pass


class InvalidCursorError(Exception):
    pass


def encode_cursor(post: Post) -> str:
    raw = f"{post.created_at.isoformat()}|{post.id}"
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        stamp, post_id = base64.urlsafe_b64decode(padded.encode()).decode().split("|")
        return datetime.fromisoformat(stamp), uuid.UUID(post_id)
    except (ValueError, binascii.Error, UnicodeDecodeError) as exc:
        raise InvalidCursorError from exc


class PostService:
    def __init__(self, repo: PostRepository, tags: TagRepository, media: MediaService) -> None:
        self.repo = repo
        self.tags = tags
        self.media = media

    def create(self, author: User, data: PostCreate) -> Post:
        assets = self.media.claim(author, [m.asset_id for m in data.media])
        tags = self.tags.get_or_create(data.tags)
        return self.repo.add(author.id, data, assets, tags)

    def get(self, post_id: uuid.UUID) -> Post:
        post = self.repo.get(post_id)
        if post is None:
            raise PostNotFoundError
        return post

    def delete(self, user: User, post_id: uuid.UUID) -> None:
        post = self.get(post_id)
        if post.author_id != user.id:
            raise NotPostOwnerError
        assets = [m.asset for m in post.media if m.asset is not None]
        self.repo.delete(post)
        self.media.release(assets)  # remove stored files nothing references any more

    def feed(self, *, limit: int, cursor: str | None) -> tuple[list[Post], str | None]:
        before = decode_cursor(cursor) if cursor else None
        rows = self.repo.feed(limit=limit + 1, before=before)
        page = rows[:limit]
        next_cursor = encode_cursor(page[-1]) if len(rows) > limit else None
        return page, next_cursor
