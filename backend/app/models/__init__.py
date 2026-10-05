"""Import every model here so Base.metadata (and Alembic) sees all tables."""

from app.models.media import MediaAsset
from app.models.post import Post, PostMedia
from app.models.profile import Profile
from app.models.revoked_token import RevokedToken
from app.models.social import Comment, Follow, PostLike, PostSave
from app.models.story import Story, StoryLike, StoryMedia, StorySave, story_tags
from app.models.tag import Tag, post_tags
from app.models.user import User

# Columns that reference a MediaAsset. An asset referenced by none of them is
# "unattached" (freshly uploaded or orphaned) and may be deleted/cleaned up.
ASSET_REFERENCES = [
    PostMedia.asset_id,
    StoryMedia.asset_id,
    Story.cover_asset_id,
    Profile.avatar_asset_id,
    Profile.cover_asset_id,
]

__all__ = [
    "ASSET_REFERENCES",
    "Comment",
    "Follow",
    "MediaAsset",
    "Post",
    "PostLike",
    "PostSave",
    "PostMedia",
    "Profile",
    "RevokedToken",
    "Story",
    "StoryLike",
    "StoryMedia",
    "StorySave",
    "Tag",
    "User",
    "post_tags",
    "story_tags",
]
