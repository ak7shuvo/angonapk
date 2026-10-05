import uuid

import pytest

from app.models import Notification, Report, User
from app.services.report_service import DAILY_REPORT_LIMIT
from tests.helpers import API, make_admin, make_user


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


@pytest.fixture
def bob(client):
    return make_user(client, "bob_bd")


@pytest.fixture
def admin(client, db):
    return make_admin(client, db)


def new_post(client, who, body="a post") -> str:
    return client.post(f"{API}/posts", headers=who["headers"], json={"body": body}).json()["id"]


def new_story(client, who, publish=True) -> str:
    res = client.post(
        f"{API}/stories",
        headers=who["headers"],
        json={
            "title": "Jaflong",
            "content": "Stones and water.",
            "status": "published" if publish else "draft",
        },
    )
    assert res.status_code == 201, res.text
    return res.json()["id"]


def report(client, who, target_type, target_id, reason="spam", **extra):
    return client.post(
        f"{API}/reports",
        headers=who["headers"],
        json={"target_type": target_type, "target_id": str(target_id), "reason": reason, **extra},
    )


# --- filing a report --------------------------------------------------------------


def test_reporting_requires_auth(client):
    res = client.post(
        f"{API}/reports",
        json={"target_type": "post", "target_id": str(uuid.uuid4()), "reason": "spam"},
    )
    assert res.status_code == 401


@pytest.mark.parametrize("kind", ["post", "story", "comment", "user"])
def test_report_each_target_type(client, alice, bob, kind):
    pid = new_post(client, alice)
    target = {
        "post": pid,
        "story": new_story(client, alice),
        "comment": client.post(
            f"{API}/posts/{pid}/comments", headers=alice["headers"], json={"body": "hi"}
        ).json()["id"],
        "user": alice["user"]["id"],
    }[kind]
    res = report(client, bob, kind, target, "harassment", details="  rude  ")
    assert res.status_code == 201, res.text
    body = res.json()
    assert body["status"] == "open" and body["reason"] == "harassment"
    assert "details" not in body and "reporter" not in body  # reporter sees a receipt only


def test_details_are_trimmed_and_stored(client, db, alice, bob):
    pid = new_post(client, alice)
    report(client, bob, "post", pid, "other", details="  looks like an ad  ")
    assert db.query(Report).one().details == "looks like an ad"
    report(client, make_user(client, "carol_bd"), "post", pid, "other", details="   ")
    assert sorted(r.details or "" for r in db.query(Report)) == ["", "looks like an ad"]


def test_cannot_report_yourself_or_your_content(client, alice):
    pid = new_post(client, alice)
    assert report(client, alice, "post", pid).status_code == 400
    assert report(client, alice, "story", new_story(client, alice)).status_code == 400
    assert report(client, alice, "user", alice["user"]["id"]).status_code == 400


def test_duplicate_reports_are_rejected(client, alice, bob):
    pid = new_post(client, alice)
    assert report(client, bob, "post", pid).status_code == 201
    again = report(client, bob, "post", pid, "hate")
    assert again.status_code == 409
    # A different person can still report the same thing.
    assert report(client, make_user(client, "carol_bd"), "post", pid).status_code == 201


def test_missing_and_private_targets_are_404(client, alice, bob):
    assert report(client, bob, "post", uuid.uuid4()).status_code == 404
    assert report(client, bob, "user", uuid.uuid4()).status_code == 404
    draft = new_story(client, alice, publish=False)
    assert report(client, bob, "story", draft).status_code == 404  # drafts aren't public


def test_validation(client, alice, bob):
    pid = new_post(client, alice)
    assert report(client, bob, "post", pid, "because").status_code == 422
    assert report(client, bob, "album", pid).status_code == 422
    assert report(client, bob, "post", pid, details="x" * 1001).status_code == 422
    bad = client.post(
        f"{API}/reports",
        headers=bob["headers"],
        json={"target_type": "post", "target_id": "nope", "reason": "spam"},
    )
    assert bad.status_code == 422
    extra = report(client, bob, "post", pid, status="resolved")  # can't set moderation fields
    assert extra.status_code == 422


def test_daily_limit(client, db, alice, bob, monkeypatch):
    monkeypatch.setattr("app.services.report_service.DAILY_REPORT_LIMIT", 2)
    posts = [new_post(client, alice, f"p{i}") for i in range(3)]
    assert report(client, bob, "post", posts[0]).status_code == 201
    assert report(client, bob, "post", posts[1]).status_code == 201
    assert report(client, bob, "post", posts[2]).status_code == 429
    assert DAILY_REPORT_LIMIT >= 10


# --- moderation endpoints -----------------------------------------------------------


def test_admin_endpoints_need_admin(client, alice):
    rid = uuid.uuid4()
    assert client.get(f"{API}/admin/reports").status_code == 401
    assert client.get(f"{API}/admin/reports", headers=alice["headers"]).status_code == 403
    assert client.get(f"{API}/admin/reports/{rid}", headers=alice["headers"]).status_code == 403
    res = client.patch(
        f"{API}/admin/reports/{rid}", headers=alice["headers"], json={"status": "resolved"}
    )
    assert res.status_code == 403


def test_queue_lists_reports_with_target_context(client, alice, bob, admin):
    pid = new_post(client, alice, "Buy cheap watches!!!")
    report(client, bob, "post", pid, "spam", details="obvious ad")
    report(client, make_user(client, "carol_bd"), "post", pid, "spam")
    report(client, bob, "user", alice["user"]["id"], "harassment")

    res = client.get(f"{API}/admin/reports", headers=admin["headers"])
    assert res.status_code == 200
    items = res.json()["items"]
    assert len(items) == 3
    by_type = {i["target_type"]: i for i in items if i["target_type"] == "user"}
    assert by_type["user"]["target"]["preview"] == "@alice_bd"
    post_item = next(i for i in items if i["target_type"] == "post" and i["details"])
    assert post_item["reporter"]["username"] == "bob_bd"
    assert post_item["target"] == {
        "exists": True,
        "author": post_item["target"]["author"],
        "preview": "Buy cheap watches!!!",
    }
    assert post_item["target"]["author"]["username"] == "alice_bd"
    assert post_item["report_count_for_target"] == 2
    assert "email" not in str(items)

    only_users = client.get(
        f"{API}/admin/reports", headers=admin["headers"], params={"target_type": "user"}
    ).json()["items"]
    assert [i["target_type"] for i in only_users] == ["user"]


def test_queue_filters_and_paginates(client, alice, bob, admin):
    posts = [new_post(client, alice, f"p{i}") for i in range(3)]
    for p in posts:
        report(client, bob, "post", p)
    first = client.get(f"{API}/admin/reports", headers=admin["headers"], params={"limit": 2}).json()
    assert len(first["items"]) == 2 and first["next_cursor"]
    rest = client.get(
        f"{API}/admin/reports",
        headers=admin["headers"],
        params={"limit": 2, "cursor": first["next_cursor"]},
    ).json()
    assert len(rest["items"]) == 1 and rest["next_cursor"] is None
    ids = [i["id"] for i in first["items"] + rest["items"]]
    assert len(set(ids)) == 3

    assert (
        client.get(
            f"{API}/admin/reports", headers=admin["headers"], params={"status": "resolved"}
        ).json()["items"]
        == []
    )
    for bad in ({"status": "weird"}, {"target_type": "x"}, {"cursor": "garbage"}):
        assert (
            client.get(f"{API}/admin/reports", headers=admin["headers"], params=bad).status_code
            == 422
        )


def test_resolving_a_report_records_the_reviewer_and_notifies_the_reporter(
    client, db, alice, bob, admin
):
    pid = new_post(client, alice)
    rid = report(client, bob, "post", pid).json()["id"]

    res = client.patch(
        f"{API}/admin/reports/{rid}",
        headers=admin["headers"],
        json={"status": "reviewing"},
    )
    assert res.status_code == 200 and res.json()["status"] == "reviewing"
    assert db.query(Notification).count() == 0  # not final yet

    res = client.patch(
        f"{API}/admin/reports/{rid}",
        headers=admin["headers"],
        json={"status": "resolved", "resolution_note": "  removed by author  "},
    )
    body = res.json()
    assert body["status"] == "resolved" and body["resolution_note"] == "removed by author"
    assert body["reviewed_at"]
    stored = db.get(Report, uuid.UUID(rid))
    db.refresh(stored)
    assert stored.reviewed_by_id == uuid.UUID(admin["user"]["id"])

    inbox = client.get(f"{API}/notifications", headers=bob["headers"]).json()["items"]
    assert [n["type"] for n in inbox] == ["moderation"]
    assert inbox[0]["actor"] is None and inbox[0]["data"]["title"] == "Thanks for your report"

    # Re-saving a closed report doesn't notify twice.
    client.patch(
        f"{API}/admin/reports/{rid}", headers=admin["headers"], json={"status": "dismissed"}
    )
    assert db.query(Notification).filter_by(type="moderation").count() == 1
    assert client.get(f"{API}/notifications", headers=alice["headers"]).json()["items"] == []


def test_dismiss_message_differs(client, alice, bob, admin):
    rid = report(client, bob, "post", new_post(client, alice)).json()["id"]
    client.patch(
        f"{API}/admin/reports/{rid}", headers=admin["headers"], json={"status": "dismissed"}
    )
    body = client.get(f"{API}/notifications", headers=bob["headers"]).json()["items"][0]["data"][
        "body"
    ]
    assert "no violation" in body


def test_update_validation_and_404(client, alice, bob, admin):
    rid = report(client, bob, "post", new_post(client, alice)).json()["id"]
    url = f"{API}/admin/reports/{rid}"
    assert client.patch(url, headers=admin["headers"], json={"status": "open?"}).status_code == 422
    assert client.patch(url, headers=admin["headers"], json={}).status_code == 422
    forged = client.patch(
        url, headers=admin["headers"], json={"status": "resolved", "reporter_id": "x"}
    )
    assert forged.status_code == 422
    missing = client.patch(
        f"{API}/admin/reports/{uuid.uuid4()}", headers=admin["headers"], json={"status": "resolved"}
    )
    assert missing.status_code == 404
    assert (
        client.get(f"{API}/admin/reports/{uuid.uuid4()}", headers=admin["headers"]).status_code
        == 404
    )
    assert client.get(url, headers=admin["headers"]).json()["id"] == rid


def test_reports_survive_deletion_of_the_target(client, alice, bob, admin):
    pid = new_post(client, alice)
    report(client, bob, "post", pid)
    assert client.delete(f"{API}/posts/{pid}", headers=alice["headers"]).status_code == 204
    item = client.get(f"{API}/admin/reports", headers=admin["headers"]).json()["items"][0]
    assert item["target"] == {"exists": False, "author": None, "preview": None}


def test_role_cannot_be_self_assigned(client, db, alice):
    # No endpoint accepts a role; promotion is an operator action (scripts.create_admin).
    res = client.patch(f"{API}/users/me/profile", headers=alice["headers"], json={"role": "admin"})
    assert res.status_code == 422
    assert db.query(User).filter_by(username="alice_bd").one().role == "user"


def test_create_admin_script(client, db, alice):
    from scripts.create_admin import set_role

    assert client.get(f"{API}/admin/reports", headers=alice["headers"]).status_code == 403
    assert set_role(db, "nobody", "admin") == 1
    assert set_role(db, "alice_bd", "admin") == 0  # by username
    assert client.get(f"{API}/admin/reports", headers=alice["headers"]).status_code == 200
    assert set_role(db, "alice_bd@example.com", "user") == 0  # by email
    assert client.get(f"{API}/admin/reports", headers=alice["headers"]).status_code == 403
