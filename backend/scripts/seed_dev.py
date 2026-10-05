"""DEVELOPMENT SEED DATA — never run against production.

Creates clearly marked placeholder accounts (`seed_*`, display name prefixed
"[Seed]"), posts and stories linked to places in Bangladesh so every screen has
something to render during development.
All text is invented sample content, NOT verified real-world information or
real user content. Images are flat-colour placeholder PNGs, not photographs.

    cd backend && python -m scripts.seed_dev

Re-running replaces the previous seed posts. Seed accounts share the password
printed below; that is acceptable only because this refuses to run in production.
"""

import os
import struct
import zlib
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.core.config import get_settings
from app.core.security import hash_password
from app.core.text import slugify
from app.db.session import get_session_factory
from app.models import MediaAsset, Post, PostMedia, Profile, Story, User
from app.repositories.story_repository import StoryRepository
from app.repositories.tag_repository import TagRepository
from app.storage.factory import build_storage
from scripts.seed_content import (
    SEED_DRAFT,
    SEED_DRAFT_TITLE,
    SEED_PASSWORD,
    SEED_POSTS,
    SEED_STORIES,
    SEED_USERS,
    STORY_DISCLAIMER,
)
from scripts.seed_places import seed_places

WARM = [(0xB4, 0x53, 0x2A), (0x2F, 0x5D, 0x50), (0xD9, 0xA4, 0x41), (0x8C, 0x3E, 0x1D)]

__all__ = [
    "SEED_DRAFT_TITLE",
    "SEED_DRAFT",
    "SEED_PASSWORD",
    "SEED_POSTS",
    "SEED_STORIES",
    "SEED_USERS",
    "main",
]


def _png(rgb: tuple[int, int, int], w: int = 1200, h: int = 900) -> bytes:
    """Minimal flat-colour PNG (no image library dependency)."""
    row = b"\x00" + bytes(rgb) * w
    raw = row * h

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def _clear_previous(db, users: dict[str, User], storage) -> None:
    """Remove what an earlier run created so re-running never duplicates."""
    ids = [u.id for u in users.values()]
    for story in db.scalars(select(Story).where(Story.author_id.in_(ids))):
        db.delete(story)
    for post in db.scalars(select(Post).where(Post.author_id.in_(ids))):
        db.delete(post)
    db.flush()
    for asset in db.scalars(select(MediaAsset).where(MediaAsset.owner_id.in_(ids))):
        try:
            storage.delete(asset.storage_key)
        except Exception:  # noqa: BLE001 - a missing placeholder file is harmless
            pass
        db.delete(asset)
    db.flush()


def main() -> None:
    if os.environ.get("APP_ENV") == "production":
        raise SystemExit("Refusing to seed development data in production.")
    settings = get_settings()
    if settings.is_production:
        raise SystemExit("Refusing to seed development data in production.")
    storage = build_storage(settings)
    urls = []
    for i, rgb in enumerate(WARM):
        obj = storage.save(f"seed/placeholder-{i}.png", _png(rgb), "image/png")
        urls.append(obj.url)

    with get_session_factory()() as db:
        places = seed_places(db, urls)
        users: dict[str, User] = {}
        for username, display, creator, location, bio in SEED_USERS:
            user = db.scalar(select(User).where(User.username == username))
            if user is None:
                user = User(
                    email=f"{username}@seed.invalid",  # .invalid never resolves
                    username=username,
                    password_hash=hash_password(SEED_PASSWORD),
                )
                user.profile = Profile()
                db.add(user)
            user.profile.display_name = display
            user.profile.creator_type = creator
            user.profile.location = location
            user.profile.bio = f"[SEED DATA] {bio}"
            users[username] = user
        db.flush()
        _clear_previous(db, users, storage)

        tags = TagRepository(db)
        now = datetime.now(UTC)
        for username, body, location, place_slug, hours_ago, images, tag_names in SEED_POSTS:
            stamp = now - timedelta(hours=hours_ago)
            db.add(
                Post(
                    author_id=users[username].id,
                    body=body,
                    location_text=location,
                    place_id=places[place_slug].id if place_slug else None,
                    tags=tags.get_or_create(tag_names),
                    created_at=stamp,
                    updated_at=stamp,
                    media=[
                        PostMedia(
                            media_type="image",
                            url=urls[i],
                            width=1200,
                            height=900,
                            alt_text="Seed placeholder image",
                            position=pos,
                        )
                        for pos, i in enumerate(images)
                    ],
                )
            )

        stories = StoryRepository(db)
        for n, row in enumerate(SEED_STORIES):
            username, title, location, place_slug, hours_ago, cover, tag_names, paragraphs = row
            stamp = now - timedelta(hours=hours_ago)
            key = f"seed/story-cover-{n}.png"
            saved = storage.save(key, _png(WARM[cover]), "image/png")
            asset = MediaAsset(
                owner_id=users[username].id,
                storage_key=key,
                url=saved.url,
                kind="image",
                content_type="image/png",
                size_bytes=0,
                width=1200,
                height=900,
            )
            db.add(asset)
            db.flush()
            db.add(
                Story(
                    author_id=users[username].id,
                    title=title,
                    slug=stories.new_slug(slugify(title)),
                    content="\n\n".join([*paragraphs, STORY_DISCLAIMER]),
                    cover_asset_id=asset.id,
                    location_text=location,
                    place_id=places[place_slug].id,
                    tags=tags.get_or_create(tag_names),
                    status="published",
                    published_at=stamp,
                    created_at=stamp,
                    updated_at=stamp,
                )
            )

        username, title, location, place_slug, tag_names, paragraphs = SEED_DRAFT
        db.add(
            Story(
                author_id=users[username].id,
                title=title,
                slug=stories.new_slug(slugify(title)),
                content="\n\n".join([*paragraphs, STORY_DISCLAIMER]),
                location_text=location,
                place_id=places[place_slug].id,
                tags=tags.get_or_create(tag_names),
                status="draft",
            )
        )
        db.commit()
    print(
        f"Seeded {len(places)} places, {len(SEED_USERS)} users, {len(SEED_POSTS)} posts "
        f"and {len(SEED_STORIES)} stories (+1 draft) (SEED DATA)."
    )
    print(f"Log in as e.g. seed_rahim / {SEED_PASSWORD}")


if __name__ == "__main__":
    main()
