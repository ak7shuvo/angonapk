import uuid

import pytest

from app.models import Notification
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
    return client.post(f"{API}/posts", headers=who["headers"], json={"body": body}).json()["id"]


def inbox(client, who, **params) -> dict:
    res = client.get(f"{API}/notifications", headers=who["headers"], params=params)
    assert res.status_code == 200, res.text
    return res.json()


def unread(client, who) -> int:
    return client.get(f"{API}/notifications/unread-count", headers=who["headers"]).json()["unread"]


# --- auth ----------------------------------------------------------------------


def test_notification_endpoints_require_auth(client):
    nid = uuid.uuid4()
    assert client.get(f"{API}/notifications").status_code == 401
    assert client.get(f"{API}/notifications/unread-count").status_code == 401
    assert client.post(f"{API}/notifications/read-all").status_code == 401
    assert client.post(f"{API}/notifications/{nid}/read").status_code == 401


def test_empty_inbox(client, alice):
    assert inbox(client, alice) == {"items": [], "next_cursor": None}
    assert unread(client, alice) == 0


# --- producing -----------------------------------------------------------------


def test_like_notifies_the_author_once(client, alice, bob):
    pid = new_post(client, alice, "Early light over the haor")
    for _ in range(3):  # re-liking never spams
        client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    items = inbox(client, alice)["items"]
    assert len(items) == 1
    n = items[0]
    assert n["type"] == "like" and n["target_type"] == "post" and n["target_id"] == pid
    assert n["actor"]["username"] == "bob_bd" and n["is_read"] is False
    assert n["data"]["preview"] == "Early light over the haor"
    assert inbox(client, bob)["items"] == []  # the liker gets nothing


def test_unlike_retracts_the_notification(client, alice, bob):
    pid = new_post(client, alice)
    client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    assert unread(client, alice) == 1
    client.delete(f"{API}/posts/{pid}/like", headers=bob["headers"])
    assert unread(client, alice) == 0
    client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])  # liking again notifies again
    assert unread(client, alice) == 1


def test_no_self_notifications(client, alice):
    pid = new_post(client, alice)
    client.put(f"{API}/posts/{pid}/like", headers=alice["headers"])
    client.post(f"{API}/posts/{pid}/comments", headers=alice["headers"], json={"body": "mine"})
    assert inbox(client, alice)["items"] == []


def test_comment_notifies_with_snippet_and_each_comment_counts(client, alice, bob, carol):
    pid = new_post(client, alice)
    client.post(
        f"{API}/posts/{pid}/comments", headers=bob["headers"], json={"body": "  সুন্দর ছবি!  "}
    )
    cid = client.post(
        f"{API}/posts/{pid}/comments", headers=carol["headers"], json={"body": "x " * 100}
    ).json()["id"]
    items = inbox(client, alice)["items"]
    assert [n["actor"]["username"] for n in items] == ["carol_bd", "bob_bd"]  # newest first
    assert items[1]["type"] == "comment" and items[1]["data"]["preview"] == "সুন্দর ছবি!"
    assert items[1]["data"]["post_id"] == pid
    assert items[0]["data"]["preview"].endswith("…") and len(items[0]["data"]["preview"]) <= 120
    # deleting the comment retracts its notification
    client.delete(f"{API}/comments/{cid}", headers=carol["headers"])
    assert [n["actor"]["username"] for n in inbox(client, alice)["items"]] == ["bob_bd"]


def test_follow_notifies_and_unfollow_retracts(client, alice, bob):
    client.put(f"{API}/users/alice_bd/follow", headers=bob["headers"])
    client.put(f"{API}/users/alice_bd/follow", headers=bob["headers"])  # idempotent
    items = inbox(client, alice)["items"]
    assert len(items) == 1
    assert items[0]["type"] == "follow" and items[0]["target_type"] == "user"
    assert items[0]["actor"]["username"] == "bob_bd" and items[0]["data"]["username"] == "bob_bd"
    client.delete(f"{API}/users/alice_bd/follow", headers=bob["headers"])
    assert inbox(client, alice)["items"] == []


def test_story_like_notifies_with_title_and_slug(client, alice, bob):
    story = client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "জাফলংয়ের গল্প", "content": "x", "status": "published"},
    ).json()
    client.put(f"{API}/stories/{story['id']}/like", headers=bob["headers"])
    n = inbox(client, alice)["items"][0]
    assert n["target_type"] == "story" and n["target_id"] == story["id"]
    assert n["data"] == {"preview": "জাফলংয়ের গল্প", "story_slug": story["slug"]}
    client.delete(f"{API}/stories/{story['id']}/like", headers=bob["headers"])
    assert inbox(client, alice)["items"] == []


def test_deleting_content_removes_its_notifications(client, alice, bob, carol):
    pid = new_post(client, alice)
    client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    client.post(f"{API}/posts/{pid}/comments", headers=carol["headers"], json={"body": "hi"})
    story = client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "T", "content": "x", "status": "published"},
    ).json()
    client.put(f"{API}/stories/{story['id']}/like", headers=bob["headers"])
    assert unread(client, alice) == 3
    client.delete(f"{API}/posts/{pid}", headers=alice["headers"])
    assert unread(client, alice) == 1
    client.delete(f"{API}/stories/{story['id']}", headers=alice["headers"])
    assert unread(client, alice) == 0


# --- reading / state ---------------------------------------------------------


def test_mark_one_read_and_unread_filter(client, alice, bob, carol):
    pid = new_post(client, alice)
    client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    client.put(f"{API}/users/alice_bd/follow", headers=carol["headers"])
    first, second = inbox(client, alice)["items"]
    res = client.post(f"{API}/notifications/{first['id']}/read", headers=alice["headers"])
    assert res.status_code == 200 and res.json()["is_read"] is True
    assert (
        client.post(f"{API}/notifications/{first['id']}/read", headers=alice["headers"]).status_code
        == 200
    )
    assert unread(client, alice) == 1
    only_unread = inbox(client, alice, unread_only=True)["items"]
    assert [n["id"] for n in only_unread] == [second["id"]]
    assert len(inbox(client, alice)["items"]) == 2  # read ones remain in the full list


def test_mark_all_read(client, alice, bob, carol):
    for who in (bob, carol):
        client.put(f"{API}/users/alice_bd/follow", headers=who["headers"])
    assert unread(client, alice) == 2
    res = client.post(f"{API}/notifications/read-all", headers=alice["headers"])
    assert res.json() == {"unread": 0}
    assert unread(client, alice) == 0
    assert all(n["is_read"] for n in inbox(client, alice)["items"])


def test_cannot_touch_someone_elses_notifications(client, alice, bob):
    client.put(f"{API}/users/alice_bd/follow", headers=bob["headers"])
    nid = inbox(client, alice)["items"][0]["id"]
    assert client.post(f"{API}/notifications/{nid}/read", headers=bob["headers"]).status_code == 404
    assert (
        client.post(
            f"{API}/notifications/{uuid.uuid4()}/read", headers=alice["headers"]
        ).status_code
        == 404
    )
    assert unread(client, alice) == 1  # untouched
    client.post(f"{API}/notifications/read-all", headers=bob["headers"])
    assert unread(client, alice) == 1  # bob's read-all affects only bob's inbox


def test_pagination(client, alice, bob):
    for i in range(5):
        pid = new_post(client, alice, f"p{i}")
        client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    seen, cursor = [], None
    while True:
        page = inbox(client, alice, limit=2, **({"cursor": cursor} if cursor else {}))
        seen += [n["data"]["preview"] for n in page["items"]]
        cursor = page["next_cursor"]
        if not cursor:
            break
    assert seen == [f"p{i}" for i in (4, 3, 2, 1, 0)]
    assert (
        client.get(
            f"{API}/notifications", headers=alice["headers"], params={"cursor": "zz"}
        ).status_code
        == 422
    )
    assert (
        client.get(
            f"{API}/notifications", headers=alice["headers"], params={"limit": 0}
        ).status_code
        == 422
    )


def test_unknown_future_types_are_served_untouched(client, alice, db):
    from app.models import User

    user = db.query(User).filter_by(username="alice_bd").one()
    db.add(
        Notification(
            recipient_id=user.id,
            actor_id=None,
            type="booking_confirmed",
            data={"title": "Booking confirmed", "body": "See you in Sylhet"},
        )
    )
    db.commit()
    n = inbox(client, alice)["items"][0]
    assert n["type"] == "booking_confirmed" and n["actor"] is None
    assert n["data"]["title"] == "Booking confirmed"


def test_notification_failure_never_breaks_the_action(client, alice, bob, monkeypatch):
    from app.repositories.notification_repository import NotificationRepository

    def boom(self, *a, **k):
        raise RuntimeError("db hiccup")

    monkeypatch.setattr(NotificationRepository, "add", boom)
    pid = new_post(client, alice)
    res = client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    assert res.status_code == 200 and res.json()["like_count"] == 1
