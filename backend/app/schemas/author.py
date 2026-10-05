"""Public author summary shared by posts, comments, stories and lists."""

import uuid

from pydantic import BaseModel


class AuthorRead(BaseModel):
    """Public author summary. No email or private data."""

    id: uuid.UUID
    username: str
    display_name: str | None
    avatar_url: str | None = None


def author_dict(user) -> dict:
    profile = user.profile
    return {
        "id": user.id,
        "username": user.username,
        "display_name": profile.display_name if profile else None,
        "avatar_url": profile.avatar_url if profile else None,
    }
