"""DEVELOPMENT SEED DATA — never run against production.

Creates clearly marked placeholder accounts (`seed_*`, display name prefixed
"[Seed]") and posts so the feed has something to render during development.
All text is invented sample content, NOT verified real-world information or
real user content. Images are flat-colour placeholder PNGs, not photographs.

    cd backend && python -m scripts.seed_dev

Re-running replaces the previous seed posts. Seed accounts share the password
printed below; that is acceptable only because this refuses to run in production.
"""

import struct
import zlib
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.core.config import get_settings
from app.core.security import hash_password
from app.db.session import get_session_factory
from app.models import Post, PostMedia, Profile, User
from app.storage.factory import build_storage
from scripts.seed_places import seed_places

SEED_PASSWORD = "seed-password-123"  # development only

SEED_USERS = [
    ("seed_rahim", "[Seed] Rahim", "photographer", "Sylhet"),
    ("seed_nusrat", "[Seed] নুসরাত", "storyteller", "Dhaka"),
    ("seed_tanvir", "[Seed] Tanvir", "traveler", "Rajshahi"),
]

# (username, text, location, hours_ago, placeholder colours)
WARM = [(0xB4, 0x53, 0x2A), (0x2F, 0x5D, 0x50), (0xD9, 0xA4, 0x41), (0x8C, 0x3E, 0x1D)]
SEED_POSTS = [
    (
        "seed_rahim",
        "Early light over the haor. The water was completely still.",
        "Tanguar Haor, Sunamganj",
        1,
        [0, 1],
    ),
    (
        "seed_nusrat",
        "আজ সকালে জাফলংয়ে পাহাড়ের নিচে স্বচ্ছ জলের পাশে বসে ছিলাম। এখানকার নীরবতা ভাষায় প্রকাশ করা কঠিন।",
        "জাফলং, সিলেট",
        3,
        [2],
    ),
    (
        "seed_tanvir",
        "Terracotta details on an old temple wall. Worth the early start.",
        "Paharpur, Naogaon",
        8,
        [3, 0, 1],
    ),
    (
        "seed_nusrat",
        "চায়ের বাগানে বিকেল। শ্রীমঙ্গলের এই সবুজ ঢেউ দেখে মন ভরে যায়।",
        "শ্রীমঙ্গল, মৌলভীবাজার",
        20,
        [],
    ),
    (
        "seed_rahim",
        "Notes from a slow day in Sonargaon: crumbling facades, quiet lanes, good tea.",
        "Sonargaon",
        30,
        [1],
    ),
    ("seed_tanvir", "Ferry crossing at dusk.", None, 52, [0]),
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


def main() -> None:
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
        for username, display, creator, location in SEED_USERS:
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
            user.profile.bio = "[SEED DATA] Development placeholder account."
            users[username] = user
        db.flush()

        for post in db.scalars(
            select(Post).where(Post.author_id.in_([u.id for u in users.values()]))
        ):
            db.delete(post)
        db.flush()

        now = datetime.now(UTC)
        for username, body, location, hours_ago, images in SEED_POSTS:
            stamp = now - timedelta(hours=hours_ago)
            db.add(
                Post(
                    author_id=users[username].id,
                    body=body,
                    location_text=location,
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
        db.commit()
    print(
        f"Seeded {len(places)} places, {len(SEED_USERS)} users and {len(SEED_POSTS)} posts (SEED DATA)."
    )
    print(f"Log in as e.g. seed_rahim / {SEED_PASSWORD}")


if __name__ == "__main__":
    main()
