import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import MediaAsset, Post, Story, User
from app.repositories.post_repository import PostRepository
from app.repositories.social_repository import SocialRepository
from app.repositories.story_repository import StoryRepository
from app.repositories.user_repository import UserRepository
from app.schemas.profile import ProfileCounts, ProfileUpdate, PublicProfile
from app.services.media_service import AssetNotUsableError, MediaService


class ProfileError(Exception):
    status_code = 400

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class ProfileNotFoundError(ProfileError):
    status_code = 404


class ProfileInvalidError(ProfileError):
    status_code = 422


class ProfileService:
    def __init__(
        self,
        users: UserRepository,
        media: MediaService,
        social: SocialRepository,
        posts: PostRepository,
        stories: StoryRepository,
    ) -> None:
        self.users = users
        self.media = media
        self.social = social
        self.posts = posts
        self.stories = stories

    # --- edit ----------------------------------------------------------------------

    def update(self, user: User, data: ProfileUpdate) -> User:
        profile = user.profile
        fields = data.model_fields_set
        released: list[MediaAsset] = []
        for column, field in (
            ("avatar_asset_id", "avatar_media_id"),
            ("cover_asset_id", "cover_media_id"),
        ):
            if field not in fields:
                continue
            new_id: uuid.UUID | None = getattr(data, field)
            old_id = getattr(profile, column)
            if new_id == old_id:
                continue
            if new_id is not None:
                try:
                    self.media.claim(user, [new_id])
                except AssetNotUsableError as exc:
                    raise ProfileInvalidError(exc.message) from None
            old_asset = profile.avatar_asset if column == "avatar_asset_id" else profile.cover_asset
            if old_asset is not None:
                released.append(old_asset)
            setattr(profile, column, new_id)
        for name in ("display_name", "bio", "location", "creator_type"):
            if name in fields:
                setattr(profile, name, getattr(data, name))
        self.users.db.flush()
        self.users.db.expire(profile, ["avatar_asset", "cover_asset"])
        saved = self.users.save(user)
        self.media.release(released)
        return saved

    # --- public profile -------------------------------------------------------------

    def _places_count(self, db: Session, user_id: uuid.UUID) -> int:
        posts = select(Post.place_id).where(Post.author_id == user_id, Post.place_id.is_not(None))
        stories = select(Story.place_id).where(
            Story.author_id == user_id, Story.place_id.is_not(None)
        )
        union = posts.union(stories).subquery()
        return db.scalar(select(func.count()).select_from(union)) or 0

    def public(self, viewer: User, username: str) -> PublicProfile:
        user = self.users.get_by_username(username)
        if user is None or not user.is_active:
            raise ProfileNotFoundError("User not found")
        profile = user.profile
        return PublicProfile(
            id=user.id,
            username=user.username,
            display_name=profile.display_name if profile else None,
            bio=profile.bio if profile else None,
            location=profile.location if profile else None,
            creator_type=profile.creator_type if profile else None,
            avatar_url=profile.avatar_url if profile else None,
            cover_url=profile.cover_url if profile else None,
            joined_at=user.created_at,
            counts=ProfileCounts(
                posts=self.posts.count_by_author(user.id),
                stories=self.stories.published_count(user.id),
                followers=self.social.followers_count(user.id),
                following=self.social.following_count(user.id),
                places=self._places_count(self.users.db, user.id),
            ),
            is_following=user.id in self.social.following_ids(viewer.id, [user.id]),
            is_me=user.id == viewer.id,
        )

    def author(self, username: str) -> User:
        user = self.users.get_by_username(username)
        if user is None or not user.is_active:
            raise ProfileNotFoundError("User not found")
        return user
