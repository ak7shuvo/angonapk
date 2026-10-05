import uuid

from app.core.pagination import decode_cursor, encode_cursor
from app.models import Post, User
from app.repositories.place_repository import PlaceRepository
from app.repositories.post_repository import PostRepository
from app.repositories.social_repository import SocialRepository
from app.repositories.tag_repository import TagRepository
from app.schemas.post import PostCreate, PostRead
from app.services.media_service import MediaService

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 50


class PostNotFoundError(Exception):
    pass


class UnknownPlaceError(Exception):
    pass


class NotPostOwnerError(Exception):
    pass


class PostService:
    def __init__(
        self,
        repo: PostRepository,
        tags: TagRepository,
        media: MediaService,
        social: SocialRepository,
        places: PlaceRepository,
    ) -> None:
        self.repo = repo
        self.tags = tags
        self.media = media
        self.social = social
        self.places = places

    def present(self, posts: list[Post], viewer: User | None) -> list[PostRead]:
        """Serialise posts with counts and viewer-specific state (liked/saved)."""
        stats = self.social.engagement([p.id for p in posts], viewer.id if viewer else None)
        followed = (
            self.social.following_ids(viewer.id, list({p.author_id for p in posts}))
            if viewer
            else set()
        )
        out = []
        for post in posts:
            e = stats[post.id]
            out.append(
                PostRead.model_validate(post).model_copy(
                    update={
                        "like_count": e.like_count,
                        "comment_count": e.comment_count,
                        "liked_by_me": e.liked,
                        "saved_by_me": e.saved,
                        "following_author": post.author_id in followed,
                    }
                )
            )
        return out

    def create(self, author: User, data: PostCreate) -> Post:
        place = None
        if data.place_id is not None:
            place = self.places.get(data.place_id)
            if place is None:
                raise UnknownPlaceError
        assets = self.media.claim(author, [m.asset_id for m in data.media])
        tags = self.tags.get_or_create(data.tags)
        # A chosen place names the location when the author did not type one.
        location = data.location_text or (place.name if place else None)
        return self.repo.add(
            author.id,
            data,
            assets,
            tags,
            place_id=place.id if place else None,
            location_text=location,
        )

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

    def feed(
        self,
        *,
        limit: int,
        cursor: str | None,
        following_of: uuid.UUID | None = None,
        author_id: uuid.UUID | None = None,
        place_id: uuid.UUID | None = None,
        tag: str | None = None,
    ) -> tuple[list[Post], str | None]:
        before = decode_cursor(cursor) if cursor else None
        rows = self.repo.feed(
            limit=limit + 1,
            before=before,
            following_of=following_of,
            author_id=author_id,
            place_id=place_id,
            tag=tag,
        )
        page = rows[:limit]
        next_cursor = encode_cursor(page[-1].created_at, page[-1].id) if len(rows) > limit else None
        return page, next_cursor
