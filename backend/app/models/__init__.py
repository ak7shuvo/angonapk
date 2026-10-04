"""Import every model here so Base.metadata (and Alembic) sees all tables."""

from app.models.media import MediaAsset
from app.models.post import Post, PostMedia
from app.models.profile import Profile
from app.models.revoked_token import RevokedToken
from app.models.tag import Tag, post_tags
from app.models.user import User

# Columns that reference a MediaAsset. An asset referenced by none of them is
# "unattached" (freshly uploaded or orphaned) and may be deleted/cleaned up.
ASSET_REFERENCES = [PostMedia.asset_id]

__all__ = [
    "ASSET_REFERENCES",
    "MediaAsset",
    "Post",
    "PostMedia",
    "Profile",
    "RevokedToken",
    "Tag",
    "User",
    "post_tags",
]
