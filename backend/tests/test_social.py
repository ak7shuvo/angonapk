import uuid

import pytest

from app.models import Comment, Follow, PostLike, PostSave
from tests.helpers import API, make_user


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


@pytest.fixture
def bob(client):
    return make_user(client, "bob_bd")


@pytest.fixture
def carol(client):
    return make_user(client, "carol_bd")


def new_post(client, who, body="hello") -> str:
    res = client.post(f"{API}/posts", headers=who["headers"], json={"body": body})
    assert res.status_code == 201, res.text
    return res.json()["id"]


def get_post(client, who, post_id) -> dict:
    return client.get(f"{API}/posts/{post_id}", headers=who["headers"]).json()


# --- likes -----------------------------------------------------------------


def test_like_and_unlike_update_counts_and_viewer_state(client, alice, bob):
    pid = new_post(client, alice)
    res = client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    assert res.status_code == 200 and res.json() == {"liked": True, "like_count": 1}
    assert get_post(client, bob, pid)["liked_by_me"] is True
    assert get_post(client, alice, pid)["liked_by_me"] is False  # viewer-relative
    assert get_post(client, alice, pid)["like_count"] == 1

    res = client.delete(f"{API}/posts/{pid}/like", headers=bob["headers"])
    assert res.json() == {"liked": False, "like_count": 0}
    assert get_post(client, bob, pid)["liked_by_me"] is False


def test_like_is_idempotent_and_prevents_duplicates(client, alice, bob, db):
    pid = new_post(client, alice)
    for _ in range(3):
        res = client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
        assert res.json()["like_count"] == 1
    assert db.query(PostLike).count() == 1
    # Unliking something never liked is a harmless no-op.
    assert client.delete(f"{API}/posts/{pid}/like", headers=alice["headers"]).status_code == 200


def test_many_users_like_counts(client, alice, bob, carol):
    pid = new_post(client, alice)
    for who in (alice, bob, carol):
        client.put(f"{API}/posts/{pid}/like", headers=who["headers"])
    assert get_post(client, bob, pid)["like_count"] == 3


@pytest.mark.parametrize("method", ["put", "delete"])
@pytest.mark.parametrize("action", ["like", "save"])
def test_like_save_unknown_post_404_and_auth_required(client, alice, method, action):
    url = f"{API}/posts/{uuid.uuid4()}/{action}"
    assert getattr(client, method)(url, headers=alice["headers"]).status_code == 404
    assert getattr(client, method)(url).status_code == 401


# --- saves -----------------------------------------------------------------


def test_save_unsave_and_saved_list(client, alice, bob, db):
    p1, p2, p3 = (new_post(client, alice, f"post {i}") for i in range(3))
    for pid in (p1, p2):
        assert client.put(f"{API}/posts/{pid}/save", headers=bob["headers"]).status_code == 204
    client.put(f"{API}/posts/{p1}/save", headers=bob["headers"])  # duplicate: no-op
    assert db.query(PostSave).count() == 2
    assert get_post(client, bob, p1)["saved_by_me"] is True
    assert get_post(client, alice, p1)["saved_by_me"] is False  # private to the saver
    assert get_post(client, bob, p3)["saved_by_me"] is False

    saved = client.get(f"{API}/users/me/saved/posts", headers=bob["headers"]).json()
    assert [p["id"] for p in saved["items"]] == [p2, p1]  # most recently saved first
    assert all(p["saved_by_me"] for p in saved["items"])
    assert client.get(f"{API}/users/me/saved/posts", headers=alice["headers"]).json()["items"] == []

    client.delete(f"{API}/posts/{p2}/save", headers=bob["headers"])
    saved = client.get(f"{API}/users/me/saved/posts", headers=bob["headers"]).json()
    assert [p["id"] for p in saved["items"]] == [p1]


def test_saved_posts_pagination(client, alice, bob):
    ids = [new_post(client, alice, f"p{i}") for i in range(5)]
    for pid in ids:
        client.put(f"{API}/posts/{pid}/save", headers=bob["headers"])
    seen, cursor = [], None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        page = client.get(
            f"{API}/users/me/saved/posts", headers=bob["headers"], params=params
        ).json()
        seen += [p["id"] for p in page["items"]]
        cursor = page["next_cursor"]
        if not cursor:
            break
    assert seen == ids[::-1]


# --- comments --------------------------------------------------------------


def test_comment_create_list_count_and_delete_own(client, alice, bob):
    pid = new_post(client, alice)
    res = client.post(
        f"{API}/posts/{pid}/comments", headers=bob["headers"], json={"body": "  সুন্দর ছবি!  "}
    )
    assert res.status_code == 201
    comment = res.json()
    assert comment["body"] == "সুন্দর ছবি!" and comment["is_mine"] is True
    assert comment["author"]["username"] == "bob_bd"
    client.post(f"{API}/posts/{pid}/comments", headers=alice["headers"], json={"body": "Thanks!"})

    assert get_post(client, bob, pid)["comment_count"] == 2
    listing = client.get(f"{API}/posts/{pid}/comments", headers=bob["headers"]).json()
    assert [c["body"] for c in listing["items"]] == ["সুন্দর ছবি!", "Thanks!"]  # oldest first
    assert [c["is_mine"] for c in listing["items"]] == [True, False]  # viewer-relative

    assert (
        client.delete(f"{API}/comments/{comment['id']}", headers=bob["headers"]).status_code == 204
    )
    assert get_post(client, bob, pid)["comment_count"] == 1
    assert (
        client.delete(f"{API}/comments/{comment['id']}", headers=bob["headers"]).status_code == 404
    )


def test_cannot_delete_someone_elses_comment(client, alice, bob, db):
    pid = new_post(client, alice)
    cid = client.post(
        f"{API}/posts/{pid}/comments", headers=bob["headers"], json={"body": "hi"}
    ).json()["id"]
    # Not even the post's author may delete it through this endpoint.
    assert client.delete(f"{API}/comments/{cid}", headers=alice["headers"]).status_code == 403
    assert db.query(Comment).count() == 1
    assert client.delete(f"{API}/comments/{cid}").status_code == 401


@pytest.mark.parametrize("body", ["", "   ", "x" * 1001])
def test_comment_validation(client, alice, body):
    pid = new_post(client, alice)
    assert (
        client.post(
            f"{API}/posts/{pid}/comments", headers=alice["headers"], json={"body": body}
        ).status_code
        == 422
    )
    assert (
        client.post(
            f"{API}/posts/{pid}/comments",
            headers=alice["headers"],
            json={"body": "ok", "post_id": pid},
        ).status_code
        == 422
    )


def test_comments_on_missing_post_and_auth(client, alice):
    url = f"{API}/posts/{uuid.uuid4()}/comments"
    assert client.get(url, headers=alice["headers"]).status_code == 404
    assert client.post(url, headers=alice["headers"], json={"body": "x"}).status_code == 404
    assert client.get(url).status_code == 401


def test_comment_pagination(client, alice):
    pid = new_post(client, alice)
    for i in range(5):
        client.post(f"{API}/posts/{pid}/comments", headers=alice["headers"], json={"body": f"c{i}"})
    seen, cursor = [], None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        page = client.get(
            f"{API}/posts/{pid}/comments", headers=alice["headers"], params=params
        ).json()
        seen += [c["body"] for c in page["items"]]
        cursor = page["next_cursor"]
        if not cursor:
            break
    assert seen == [f"c{i}" for i in range(5)]
    assert (
        client.get(
            f"{API}/posts/{pid}/comments", headers=alice["headers"], params={"cursor": "zzz"}
        ).status_code
        == 422
    )


def test_deleting_a_post_removes_its_social_rows(client, alice, bob, db):
    pid = new_post(client, alice)
    client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    client.put(f"{API}/posts/{pid}/save", headers=bob["headers"])
    client.post(f"{API}/posts/{pid}/comments", headers=bob["headers"], json={"body": "x"})
    assert client.delete(f"{API}/posts/{pid}", headers=alice["headers"]).status_code == 204
    # ORM-level SQLite has no FK cascade; on PostgreSQL the DB cascades. Either way the
    # post is gone and nothing is reachable through the API.
    assert client.get(f"{API}/posts/{pid}", headers=bob["headers"]).status_code == 404
    assert client.get(f"{API}/posts/{pid}/comments", headers=bob["headers"]).status_code == 404


# --- follows ---------------------------------------------------------------


def test_follow_unfollow_counts_and_idempotency(client, alice, bob, db):
    res = client.put(f"{API}/users/bob_bd/follow", headers=alice["headers"])
    assert res.status_code == 200 and res.json() == {"following": True, "followers_count": 1}
    assert (
        client.put(f"{API}/users/bob_bd/follow", headers=alice["headers"]).json()["followers_count"]
        == 1
    )
    assert db.query(Follow).count() == 1  # no duplicate row

    res = client.delete(f"{API}/users/bob_bd/follow", headers=alice["headers"])
    assert res.json() == {"following": False, "followers_count": 0}
    assert client.delete(f"{API}/users/bob_bd/follow", headers=alice["headers"]).status_code == 200


def test_cannot_follow_self_or_unknown(client, alice):
    assert client.put(f"{API}/users/alice_bd/follow", headers=alice["headers"]).status_code == 400
    assert (
        client.delete(f"{API}/users/alice_bd/follow", headers=alice["headers"]).status_code == 400
    )
    assert client.put(f"{API}/users/nobody/follow", headers=alice["headers"]).status_code == 404
    assert client.put(f"{API}/users/bob_bd/follow").status_code == 401


def test_followers_and_following_lists(client, alice, bob, carol):
    client.put(f"{API}/users/carol_bd/follow", headers=alice["headers"])
    client.put(f"{API}/users/carol_bd/follow", headers=bob["headers"])
    client.put(f"{API}/users/bob_bd/follow", headers=alice["headers"])

    followers = client.get(f"{API}/users/carol_bd/followers", headers=alice["headers"]).json()
    assert [u["username"] for u in followers["items"]] == ["bob_bd", "alice_bd"]  # newest first
    by_name = {u["username"]: u for u in followers["items"]}
    assert by_name["alice_bd"]["is_me"] is True
    assert by_name["bob_bd"]["is_following"] is True  # alice follows bob
    assert by_name["alice_bd"]["is_following"] is False

    following = client.get(f"{API}/users/alice_bd/following", headers=bob["headers"]).json()
    assert {u["username"] for u in following["items"]} == {"carol_bd", "bob_bd"}
    me = next(u for u in following["items"] if u["username"] == "bob_bd")
    assert me["is_me"] is True  # viewer is bob
    assert client.get(f"{API}/users/nobody/followers", headers=alice["headers"]).status_code == 404
    assert client.get(f"{API}/users/carol_bd/followers").status_code == 401


def test_follower_list_pagination(client, alice, bob, carol):
    for who in (alice, bob):
        client.put(f"{API}/users/carol_bd/follow", headers=who["headers"])
    first = client.get(
        f"{API}/users/carol_bd/followers", headers=alice["headers"], params={"limit": 1}
    ).json()
    assert len(first["items"]) == 1 and first["next_cursor"]
    second = client.get(
        f"{API}/users/carol_bd/followers",
        headers=alice["headers"],
        params={"limit": 1, "cursor": first["next_cursor"]},
    ).json()
    assert second["next_cursor"] is None
    assert {first["items"][0]["username"], second["items"][0]["username"]} == {"alice_bd", "bob_bd"}


def test_following_feed_scope(client, alice, bob, carol):
    new_post(client, alice, "alice post")
    new_post(client, bob, "bob post")
    new_post(client, carol, "carol post")
    client.put(f"{API}/users/bob_bd/follow", headers=alice["headers"])

    def bodies(scope):
        res = client.get(f"{API}/posts", headers=alice["headers"], params={"scope": scope})
        return [p["body"] for p in res.json()["items"]]

    assert bodies("all") == ["carol post", "bob post", "alice post"]
    assert bodies("following") == ["bob post", "alice post"]  # followed + own, not carol
    assert (
        client.get(f"{API}/posts", headers=alice["headers"], params={"scope": "x"}).status_code
        == 422
    )
    assert (
        client.get(f"{API}/posts", headers=carol["headers"], params={"scope": "following"}).json()[
            "items"
        ][0]["body"]
        == "carol post"
    )


def test_feed_stats_are_batched_per_viewer(client, alice, bob):
    ids = [new_post(client, alice, f"p{i}") for i in range(3)]
    client.put(f"{API}/posts/{ids[0]}/like", headers=bob["headers"])
    client.post(f"{API}/posts/{ids[0]}/comments", headers=bob["headers"], json={"body": "x"})
    client.put(f"{API}/posts/{ids[1]}/save", headers=bob["headers"])
    items = client.get(f"{API}/posts", headers=bob["headers"]).json()["items"]
    by_body = {p["body"]: p for p in items}
    assert (
        by_body["p0"]["like_count"],
        by_body["p0"]["comment_count"],
        by_body["p0"]["liked_by_me"],
    ) == (1, 1, True)
    assert by_body["p1"]["saved_by_me"] is True and by_body["p1"]["like_count"] == 0
    assert by_body["p2"]["liked_by_me"] is False


def test_posts_report_whether_viewer_follows_the_author(client, alice, bob):
    pid = new_post(client, bob, "by bob")
    assert get_post(client, alice, pid)["following_author"] is False
    client.put(f"{API}/users/bob_bd/follow", headers=alice["headers"])
    assert get_post(client, alice, pid)["following_author"] is True
    assert get_post(client, bob, pid)["following_author"] is False
