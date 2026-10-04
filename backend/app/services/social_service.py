import uuid

from app.core.pagination import decode_cursor, encode_cursor
from app.models import Comment, Post, User
from app.repositories.post_repository import PostRepository
from app.repositories.social_repository import SocialRepository
from app.repositories.user_repository import UserRepository
from app.schemas.social import CommentRead, UserSummary


class PostMissingError(Exception):
    pass


class CommentMissingError(Exception):
    pass


class NotCommentOwnerError(Exception):
    pass


class UserMissingError(Exception):
    pass


class SelfFollowError(Exception):
    pass


class SocialService:
    """Likes, saves, comments and follows. Every operation is idempotent where it
    can be (liking twice is not an error and never double-counts)."""

    def __init__(
        self, social: SocialRepository, posts: PostRepository, users: UserRepository
    ) -> None:
        self.social = social
        self.posts = posts
        self.users = users

    def _post(self, post_id: uuid.UUID) -> Post:
        post = self.posts.get(post_id)
        if post is None:
            raise PostMissingError
        return post

    # --- likes / saves ----------------------------------------------------------

    def like(self, user: User, post_id: uuid.UUID) -> tuple[bool, int, Post, bool]:
        """Returns (liked, like_count, post, newly_created)."""
        post = self._post(post_id)
        created = self.social.like(user.id, post.id)
        return True, self.social.like_count(post.id), post, created

    def unlike(self, user: User, post_id: uuid.UUID) -> tuple[bool, int, Post]:
        post = self._post(post_id)
        self.social.unlike(user.id, post.id)
        return False, self.social.like_count(post.id), post

    def save(self, user: User, post_id: uuid.UUID) -> None:
        self.social.save(user.id, self._post(post_id).id)

    def unsave(self, user: User, post_id: uuid.UUID) -> None:
        self.social.unsave(user.id, self._post(post_id).id)

    # --- comments ---------------------------------------------------------------

    def add_comment(self, user: User, post_id: uuid.UUID, body: str) -> tuple[Comment, Post]:
        post = self._post(post_id)
        return self.social.add_comment(post.id, user.id, body), post

    def delete_comment(self, user: User, comment_id: uuid.UUID) -> Comment:
        comment = self.social.get_comment(comment_id)
        if comment is None:
            raise CommentMissingError
        if comment.author_id != user.id:
            raise NotCommentOwnerError
        self.social.delete_comment(comment)
        return comment

    def comments(
        self, viewer: User, post_id: uuid.UUID, *, limit: int, cursor: str | None
    ) -> tuple[list[CommentRead], str | None]:
        self._post(post_id)
        after = decode_cursor(cursor) if cursor else None
        rows = self.social.comments_page(post_id, limit=limit + 1, after=after)
        page = rows[:limit]
        items = [
            CommentRead.model_validate(c).model_copy(update={"is_mine": c.author_id == viewer.id})
            for c in page
        ]
        next_cursor = encode_cursor(page[-1].created_at, page[-1].id) if len(rows) > limit else None
        return items, next_cursor

    # --- follows ----------------------------------------------------------------

    def _target(self, username: str) -> User:
        user = self.users.get_by_username(username)
        if user is None or not user.is_active:
            raise UserMissingError
        return user

    def follow(self, me: User, username: str) -> tuple[User, int, bool]:
        """Returns (target, followers_count, newly_created)."""
        target = self._target(username)
        if target.id == me.id:
            raise SelfFollowError
        created = self.social.follow(me.id, target.id)
        return target, self.social.followers_count(target.id), created

    def unfollow(self, me: User, username: str) -> tuple[User, int]:
        target = self._target(username)
        if target.id == me.id:
            raise SelfFollowError
        self.social.unfollow(me.id, target.id)
        return target, self.social.followers_count(target.id)

    def _summaries(self, viewer: User, rows: list[tuple[User, object]]) -> list[UserSummary]:
        followed = self.social.following_ids(viewer.id, [u.id for u, _ in rows])
        return [
            user_summary(u, is_following=u.id in followed, is_me=u.id == viewer.id) for u, _ in rows
        ]

    def followers(
        self, viewer: User, username: str, *, limit: int, cursor: str | None
    ) -> tuple[list[UserSummary], str | None]:
        target = self._target(username)
        before = decode_cursor(cursor) if cursor else None
        rows = self.social.followers_page(target.id, limit=limit + 1, before=before)
        return self._page(viewer, rows, limit)

    def following(
        self, viewer: User, username: str, *, limit: int, cursor: str | None
    ) -> tuple[list[UserSummary], str | None]:
        target = self._target(username)
        before = decode_cursor(cursor) if cursor else None
        rows = self.social.following_page(target.id, limit=limit + 1, before=before)
        return self._page(viewer, rows, limit)

    def _page(self, viewer: User, rows, limit: int) -> tuple[list[UserSummary], str | None]:
        page = rows[:limit]
        next_cursor = encode_cursor(page[-1][1], page[-1][0].id) if len(rows) > limit else None
        return self._summaries(viewer, page), next_cursor

    # --- saved ------------------------------------------------------------------

    def saved_posts(self, me: User, *, limit: int, cursor: str | None):
        before = decode_cursor(cursor) if cursor else None
        rows = self.social.saved_posts(me.id, limit=limit + 1, before=before)
        page = rows[:limit]
        next_cursor = encode_cursor(page[-1][1], page[-1][0].id) if len(rows) > limit else None
        return [p for p, _ in page], next_cursor


def user_summary(user: User, *, is_following: bool, is_me: bool) -> UserSummary:
    profile = user.profile
    return UserSummary(
        id=user.id,
        username=user.username,
        display_name=profile.display_name if profile else None,
        creator_type=profile.creator_type if profile else None,
        is_following=is_following,
        is_me=is_me,
    )
