import uuid
from datetime import UTC, datetime, timedelta

import pytest

from app.models import MediaAsset, Post, PostMedia, User
from tests.helpers import API, image_bytes, make_user, upload_id


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


@pytest.fixture
def bob(client):
    return make_user(client, "bob_bd")


def create(client, who, **body):
    return client.post(f"{API}/posts", headers=who["headers"], json=body)


# --- create -----------------------------------------------------------------


def test_create_text_post(client, alice):
    res = create(
        client, alice, body="  I visited Jaflong today.  ", location_text="Jaflong, Sylhet"
    )
    assert res.status_code == 201
    post = res.json()
    assert post["body"] == "I visited Jaflong today."
    assert post["location_text"] == "Jaflong, Sylhet"
    assert post["place_id"] is None
    assert post["media"] == []
    assert post["author"] == {
        "id": alice["user"]["id"],
        "username": "alice_bd",
        "display_name": None,
    }
    assert "email" not in post["author"]
    assert post["created_at"].endswith("+00:00")


def test_create_bengali_post(client, alice):
    res = create(
        client, alice, body="আজ জাফলং গিয়েছিলাম। পাহাড়ের নিচে স্বচ্ছ জল।", location_text="জাফলং, সিলেট"
    )
    assert res.status_code == 201
    assert res.json()["body"].startswith("আজ জাফলং")
    got = client.get(f"{API}/posts/{res.json()['id']}", headers=alice["headers"]).json()
    assert got["location_text"] == "জাফলং, সিলেট"


def test_create_post_with_ordered_media(client, alice, db):
    ids = [upload_id(client, alice, data=image_bytes(size=(100 + i, 80))) for i in range(3)]
    res = create(
        client,
        alice,
        body="Three photos",
        media=[
            {"asset_id": ids[2], "alt_text": "River"},
            {"asset_id": ids[0]},
            {"asset_id": ids[1]},
        ],
    )
    assert res.status_code == 201
    media = res.json()["media"]
    assert [m["width"] for m in media] == [102, 100, 101]  # request order preserved
    assert media[0]["alt_text"] == "River" and media[0]["type"] == "image"
    assert media[0]["url"].startswith("/media/u/")
    assert [m.position for m in db.query(PostMedia).order_by(PostMedia.position)] == [0, 1, 2]


def test_author_comes_from_token_not_body(client, alice, bob):
    res = create(client, alice, body="hi", author_id=bob["user"]["id"])
    assert res.status_code == 422  # unknown fields are rejected
    res = create(client, alice, body="hi")
    assert res.json()["author"]["username"] == "alice_bd"


def test_post_links_to_user_and_profile(client, alice, db):
    client.patch(
        f"{API}/users/me/profile",
        headers=alice["headers"],
        json={"display_name": "Alice", "creator_type": "traveler"},
    )
    post_id = create(client, alice, body="hello").json()["id"]
    post = db.get(Post, uuid.UUID(post_id))
    assert post.author_id == db.query(User).filter_by(username="alice_bd").one().id
    assert post.author.profile.display_name == "Alice"
    feed = client.get(f"{API}/posts", headers=alice["headers"]).json()
    assert feed["items"][0]["author"]["display_name"] == "Alice"


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"body": ""},
        {"body": "   "},
        {"body": "x" * 2001},
        {"body": "ok", "location_text": "x" * 121},
        {"body": "ok", "media": [{"url": "https://example.com/a.jpg"}]},  # URLs are not accepted
        {"body": "ok", "media": [{"asset_id": "not-a-uuid"}]},
        {"body": "ok", "media": [{"asset_id": str(uuid.uuid4())}] * 11},
        {"body": "ok", "tags": ["x"]},
        {"body": "ok", "tags": ["has space"]},
        {"body": "ok", "tags": [f"tag{i}" for i in range(9)]},
        {"body": "ok", "place_id": str(uuid.uuid4())},
    ],
)
def test_create_invalid_input(client, alice, body):
    assert create(client, alice, **body).status_code == 422


def test_media_only_post_is_allowed(client, alice):
    asset = upload_id(client, alice)
    assert create(client, alice, media=[{"asset_id": asset}]).status_code == 201


# --- authorization ----------------------------------------------------------


def test_all_post_endpoints_require_auth(client, alice):
    post_id = create(client, alice, body="x").json()["id"]
    assert client.post(f"{API}/posts", json={"body": "x"}).status_code == 401
    assert client.get(f"{API}/posts").status_code == 401
    assert client.get(f"{API}/posts/{post_id}").status_code == 401
    assert client.delete(f"{API}/posts/{post_id}").status_code == 401
    bad = {"Authorization": "Bearer junk"}
    assert client.get(f"{API}/posts", headers=bad).status_code == 401


# --- feed & pagination ------------------------------------------------------


def test_feed_is_newest_first_and_mixes_authors(client, alice, bob):
    create(client, alice, body="first")
    create(client, bob, body="second")
    create(client, alice, body="third")
    items = client.get(f"{API}/posts", headers=alice["headers"]).json()["items"]
    assert [p["body"] for p in items] == ["third", "second", "first"]
    assert [p["author"]["username"] for p in items] == ["alice_bd", "bob_bd", "alice_bd"]


def test_empty_feed(client, alice):
    res = client.get(f"{API}/posts", headers=alice["headers"])
    assert res.status_code == 200
    assert res.json() == {"items": [], "next_cursor": None}


def test_pagination_walks_all_posts_without_gaps_or_duplicates(client, alice):
    for i in range(7):
        create(client, alice, body=f"post {i}")
    seen, cursor, pages = [], None, 0
    while True:
        params = {"limit": 3, **({"cursor": cursor} if cursor else {})}
        page = client.get(f"{API}/posts", headers=alice["headers"], params=params).json()
        seen += [p["body"] for p in page["items"]]
        pages += 1
        cursor = page["next_cursor"]
        if cursor is None:
            break
    assert pages == 3
    assert seen == [f"post {i}" for i in range(6, -1, -1)]


def test_exact_multiple_has_no_trailing_cursor(client, alice):
    for i in range(4):
        create(client, alice, body=str(i))
    page = client.get(f"{API}/posts", headers=alice["headers"], params={"limit": 4}).json()
    assert len(page["items"]) == 4 and page["next_cursor"] is None


def test_pagination_is_stable_when_new_posts_arrive(client, alice):
    for i in range(4):
        create(client, alice, body=f"old {i}")
    first = client.get(f"{API}/posts", headers=alice["headers"], params={"limit": 2}).json()
    create(client, alice, body="brand new")  # arrives between page requests
    second = client.get(
        f"{API}/posts",
        headers=alice["headers"],
        params={"limit": 2, "cursor": first["next_cursor"]},
    ).json()
    bodies = [p["body"] for p in first["items"] + second["items"]]
    assert bodies == ["old 3", "old 2", "old 1", "old 0"]  # no duplicate, no skip


def test_pagination_with_identical_timestamps(client, alice, db):
    user = db.query(User).one()
    stamp = datetime(2026, 1, 1, tzinfo=UTC)
    for i in range(5):
        db.add(Post(author_id=user.id, body=f"tie {i}", created_at=stamp, updated_at=stamp))
    db.add(
        Post(
            author_id=user.id, body="newer", created_at=stamp + timedelta(days=1), updated_at=stamp
        )
    )
    db.commit()
    seen, cursor = [], None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        page = client.get(f"{API}/posts", headers=alice["headers"], params=params).json()
        seen += [p["body"] for p in page["items"]]
        cursor = page["next_cursor"]
        if not cursor:
            break
    assert len(seen) == 6 and len(set(seen)) == 6 and seen[0] == "newer"


@pytest.mark.parametrize(
    "params", [{"limit": 0}, {"limit": 51}, {"limit": "x"}, {"cursor": "!!!"}, {"cursor": "YWJj"}]
)
def test_feed_rejects_bad_params(client, alice, params):
    assert client.get(f"{API}/posts", headers=alice["headers"], params=params).status_code == 422


# --- retrieve ---------------------------------------------------------------


def test_get_single_post(client, alice, bob):
    asset = upload_id(client, alice)
    post_id = create(client, alice, body="hello", media=[{"asset_id": asset}]).json()["id"]
    res = client.get(f"{API}/posts/{post_id}", headers=bob["headers"])
    assert res.status_code == 200
    assert res.json()["id"] == post_id and res.json()["media"][0]["url"].startswith("/media/u/")


def test_get_unknown_or_malformed_id(client, alice):
    assert client.get(f"{API}/posts/{uuid.uuid4()}", headers=alice["headers"]).status_code == 404
    assert client.get(f"{API}/posts/not-a-uuid", headers=alice["headers"]).status_code == 422


# --- delete / ownership -----------------------------------------------------


def test_owner_can_delete_post_and_its_media(client, alice, db, storage):
    asset = upload_id(client, alice)
    post = create(client, alice, body="bye", media=[{"asset_id": asset}]).json()
    stored = next(storage.root.rglob("*.png"))
    assert stored.exists()
    assert client.delete(f"{API}/posts/{post['id']}", headers=alice["headers"]).status_code == 204
    assert client.get(f"{API}/posts/{post['id']}", headers=alice["headers"]).status_code == 404
    assert db.query(PostMedia).count() == 0
    assert db.query(MediaAsset).count() == 0  # asset row removed...
    assert not stored.exists()  # ...and so is the stored file
    assert client.get(f"{API}/posts", headers=alice["headers"]).json()["items"] == []


def test_non_owner_cannot_delete(client, alice, bob):
    post_id = create(client, alice, body="mine").json()["id"]
    res = client.delete(f"{API}/posts/{post_id}", headers=bob["headers"])
    assert res.status_code == 403
    assert client.get(f"{API}/posts/{post_id}", headers=alice["headers"]).status_code == 200


def test_delete_unknown_post(client, alice):
    assert client.delete(f"{API}/posts/{uuid.uuid4()}", headers=alice["headers"]).status_code == 404


# --- development seed -------------------------------------------------------


def test_seed_script_populates_feed_and_refuses_production(client, db_engine, monkeypatch):
    from sqlalchemy.orm import sessionmaker

    from app.core.config import get_settings
    from scripts import seed_dev

    factory = sessionmaker(bind=db_engine, expire_on_commit=False)
    monkeypatch.setattr(seed_dev, "get_session_factory", lambda: factory)
    seed_dev.main()
    seed_dev.main()  # idempotent: replaces its own posts

    login = client.post(
        f"{API}/auth/login", json={"identifier": "seed_rahim", "password": seed_dev.SEED_PASSWORD}
    )
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    items = client.get(f"{API}/posts", headers=headers, params={"limit": 50}).json()["items"]
    assert len(items) == len(seed_dev.SEED_POSTS)
    assert all(p["author"]["display_name"].startswith("[Seed]") for p in items)
    assert any("জাফলং" in (p["body"] or "") for p in items)

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("SECRET_KEY", "x" * 40)
    get_settings.cache_clear()
    try:
        with pytest.raises(SystemExit):
            seed_dev.main()
    finally:
        get_settings.cache_clear()


# --- tags -------------------------------------------------------------------


def test_tags_are_normalised_deduplicated_and_returned(client, alice):
    res = create(client, alice, body="x", tags=["#Culture", "culture", "Food_2", "ঐতিহ্য"])
    assert res.status_code == 201
    assert res.json()["tags"] == ["culture", "food_2", "ঐতিহ্য"]
    again = create(client, alice, body="y", tags=["CULTURE"])
    assert again.json()["tags"] == ["culture"]  # tag row reused
    feed = client.get(f"{API}/posts", headers=alice["headers"]).json()["items"]
    assert [p["tags"] for p in feed] == [["culture"], ["culture", "food_2", "ঐতিহ্য"]]
