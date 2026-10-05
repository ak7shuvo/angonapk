import uuid

import pytest
from PIL import Image

from app.models import MediaAsset
from tests.helpers import API, image_bytes, make_user, upload, upload_id


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


@pytest.fixture
def bob(client):
    return make_user(client, "bob_bd")


def patch(client, who, **body):
    return client.patch(f"{API}/users/me/profile", headers=who["headers"], json=body)


def avatar_upload(client, who, size=(300, 200)):
    return client.post(
        f"{API}/media",
        headers=who["headers"],
        params={"purpose": "avatar"},
        files={"file": ("a.png", image_bytes(size=size), "image/png")},
    )


# --- reserved usernames -----------------------------------------------------


@pytest.mark.parametrize("name", ["admin", "Angon", "support", "root"])
def test_reserved_usernames_rejected(client, name):
    res = client.post(
        f"{API}/auth/register",
        json={"email": "x@example.com", "username": name, "password": "correct-horse-1"},
    )
    assert res.status_code == 422


# --- avatar upload purpose --------------------------------------------------


def test_avatar_purpose_crops_to_square(client, alice, storage):
    res = avatar_upload(client, alice, size=(900, 300))
    assert res.status_code == 201
    body = res.json()
    assert (body["width"], body["height"]) == (512, 512)
    assert Image.open(storage.root / body["url"].removeprefix("/media/")).size == (512, 512)


def test_unknown_upload_purpose_rejected(client, alice):
    res = client.post(
        f"{API}/media",
        headers=alice["headers"],
        params={"purpose": "malware"},
        files={"file": ("a.png", image_bytes(), "image/png")},
    )
    assert res.status_code == 422


# --- edit profile -----------------------------------------------------------


def test_set_avatar_and_cover_then_read_everywhere(client, alice, bob):
    avatar = avatar_upload(client, alice).json()
    cover = upload(client, alice).json()
    res = patch(client, alice, avatar_media_id=avatar["id"], cover_media_id=cover["id"])
    assert res.status_code == 200
    profile = res.json()["profile"]
    assert profile["avatar_url"] == avatar["url"] and profile["cover_url"] == cover["url"]
    me = client.get(f"{API}/users/me", headers=alice["headers"]).json()
    assert me["profile"]["avatar_url"] == avatar["url"]

    # The avatar shows up on posts, comments and in lists for other people.
    pid = client.post(f"{API}/posts", headers=alice["headers"], json={"body": "hi"}).json()["id"]
    assert (
        client.get(f"{API}/posts/{pid}", headers=bob["headers"]).json()["author"]["avatar_url"]
        == avatar["url"]
    )
    client.post(f"{API}/posts/{pid}/comments", headers=alice["headers"], json={"body": "c"})
    comments = client.get(f"{API}/posts/{pid}/comments", headers=bob["headers"]).json()["items"]
    assert comments[0]["author"]["avatar_url"] == avatar["url"]
    client.put(f"{API}/users/alice_bd/follow", headers=bob["headers"])
    followers = client.get(f"{API}/users/alice_bd/followers", headers=bob["headers"]).json()[
        "items"
    ]
    assert followers[0]["avatar_url"] is None  # bob has none; alice's own list entry is bob
    following = client.get(f"{API}/users/bob_bd/following", headers=bob["headers"]).json()["items"]
    assert following[0]["avatar_url"] == avatar["url"]
    story = client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "T", "content": "C", "status": "published"},
    ).json()
    assert story["author"]["avatar_url"] == avatar["url"]


def test_replacing_and_removing_avatar_deletes_old_file(client, alice, db, storage):
    first = avatar_upload(client, alice).json()
    patch(client, alice, avatar_media_id=first["id"])
    second = avatar_upload(client, alice).json()
    res = patch(client, alice, avatar_media_id=second["id"])
    assert res.json()["profile"]["avatar_url"] == second["url"]
    assert db.get(MediaAsset, uuid.UUID(first["id"])) is None  # replaced image removed
    assert not (storage.root / first["url"].removeprefix("/media/")).exists()
    assert (storage.root / second["url"].removeprefix("/media/")).exists()

    res = patch(client, alice, avatar_media_id=None)
    assert res.json()["profile"]["avatar_url"] is None
    assert db.query(MediaAsset).count() == 0


def test_avatar_must_be_own_unused_upload(client, alice, bob):
    theirs = upload_id(client, bob)
    assert patch(client, alice, avatar_media_id=theirs).status_code == 422
    assert patch(client, alice, avatar_media_id=str(uuid.uuid4())).status_code == 422
    mine = upload_id(client, alice)
    client.post(f"{API}/posts", headers=alice["headers"], json={"media": [{"asset_id": mine}]})
    assert patch(client, alice, avatar_media_id=mine).status_code == 422  # already in a post
    # Omitting the fields leaves existing images alone.
    ok = avatar_upload(client, alice).json()
    patch(client, alice, avatar_media_id=ok["id"])
    assert patch(client, alice, bio="hello").json()["profile"]["avatar_url"] == ok["url"]


def test_cannot_patch_other_accounts_via_body(client, alice):
    assert patch(client, alice, username="x").status_code == 422
    assert patch(client, alice, user_id=str(uuid.uuid4())).status_code == 422


# --- public profile ---------------------------------------------------------


def test_public_profile_counts_and_flags(client, alice, bob):
    patch(
        client,
        alice,
        display_name="Alice",
        bio="Chasing haors.",
        location="Sylhet",
        creator_type="photographer",
    )
    for i in range(3):
        client.post(f"{API}/posts", headers=alice["headers"], json={"body": f"p{i}"})
    client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "Pub", "content": "x", "status": "published"},
    )
    client.post(f"{API}/stories", headers=alice["headers"], json={"title": "Draft", "content": "x"})
    client.put(f"{API}/users/alice_bd/follow", headers=bob["headers"])
    client.put(f"{API}/users/bob_bd/follow", headers=alice["headers"])

    prof = client.get(f"{API}/users/alice_bd", headers=bob["headers"]).json()
    assert prof["username"] == "alice_bd" and prof["display_name"] == "Alice"
    assert prof["bio"] == "Chasing haors." and prof["creator_type"] == "photographer"
    assert prof["counts"] == {"posts": 3, "stories": 1, "followers": 1, "following": 1, "places": 0}
    assert prof["is_following"] is True and prof["is_me"] is False
    assert "email" not in prof
    own = client.get(f"{API}/users/alice_bd", headers=alice["headers"]).json()
    assert own["is_me"] is True and own["is_following"] is False
    # Case-insensitive lookup; unknown → 404; auth required.
    assert client.get(f"{API}/users/ALICE_BD", headers=bob["headers"]).status_code == 200
    assert client.get(f"{API}/users/ghost", headers=bob["headers"]).status_code == 404
    assert client.get(f"{API}/users/alice_bd").status_code == 401


def test_users_posts_endpoint_paginates_and_filters(client, alice, bob):
    ids = [
        client.post(f"{API}/posts", headers=alice["headers"], json={"body": f"a{i}"}).json()["id"]
        for i in range(5)
    ]
    client.post(f"{API}/posts", headers=bob["headers"], json={"body": "bob's"})
    seen, cursor = [], None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        page = client.get(
            f"{API}/users/alice_bd/posts", headers=bob["headers"], params=params
        ).json()
        seen += [p["id"] for p in page["items"]]
        cursor = page["next_cursor"]
        if not cursor:
            break
    assert seen == ids[::-1]
    assert client.get(f"{API}/users/ghost/posts", headers=bob["headers"]).status_code == 404
    assert client.get(f"{API}/users/alice_bd/posts").status_code == 401
    assert (
        client.get(
            f"{API}/users/alice_bd/posts", headers=bob["headers"], params={"cursor": "zz"}
        ).status_code
        == 422
    )


def test_profile_posts_show_viewer_state(client, alice, bob):
    pid = client.post(f"{API}/posts", headers=alice["headers"], json={"body": "x"}).json()["id"]
    client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    items = client.get(f"{API}/users/alice_bd/posts", headers=bob["headers"]).json()["items"]
    assert items[0]["liked_by_me"] is True and items[0]["like_count"] == 1
