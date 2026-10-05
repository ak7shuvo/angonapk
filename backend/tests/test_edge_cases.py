"""Error paths and boundary behaviour that the feature tests don't reach."""

import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.main import app
from app.models import User
from app.repositories.media_repository import MediaRepository
from app.repositories.user_repository import UserRepository
from tests.helpers import API, image_bytes, make_user, upload

BAD_CURSOR = {"cursor": "definitely-not-a-cursor"}


@pytest.fixture
def me(client):
    return make_user(client, "edge_bd")


def new_story(client, who) -> str:
    res = client.post(
        f"{API}/stories",
        headers=who["headers"],
        json={"title": "A story", "content": "Body.", "status": "published"},
    )
    assert res.status_code == 201, res.text
    return res.json()["id"]


@pytest.mark.parametrize(
    "path",
    [
        "/posts",
        "/stories",
        "/stories/mine",
        "/users/me/saved/posts",
        "/users/me/saved/stories",
        "/users/edge_bd/followers",
        "/users/edge_bd/following",
        "/users/edge_bd/posts",
        "/notifications",
        "/admin/reports",
    ],
)
def test_garbage_cursors_are_a_422_not_a_500(client, me, db, path):
    if path.startswith("/admin"):
        db.query(User).filter_by(username="edge_bd").one().role = "admin"
        db.commit()
    res = client.get(f"{API}{path}", headers=me["headers"], params=BAD_CURSOR)
    assert res.status_code == 422, (path, res.text)


def test_place_sub_resources_validate_cursors_and_slugs(client, me, db):
    from app.models import Place

    db.add(Place(slug="here", name="Here", latitude=24.0, longitude=90.0))
    db.commit()
    for sub in ("posts", "stories", "photos"):
        bad = client.get(f"{API}/places/here/{sub}", headers=me["headers"], params=BAD_CURSOR)
        assert bad.status_code == 422, sub
    for sub in ("posts", "stories", "photos", "creators"):
        assert client.get(f"{API}/places/nowhere/{sub}", headers=me["headers"]).status_code == 404


def test_story_like_save_and_unlike_unsave_roundtrip_and_404s(client, me):
    sid = new_story(client, me)
    h = me["headers"]
    assert client.put(f"{API}/stories/{sid}/like", headers=h).json()["like_count"] == 1
    assert client.delete(f"{API}/stories/{sid}/like", headers=h).json()["like_count"] == 0
    assert client.put(f"{API}/stories/{sid}/save", headers=h).status_code == 204
    assert client.delete(f"{API}/stories/{sid}/save", headers=h).status_code == 204
    ghost = uuid.uuid4()
    for method, path in [
        ("delete", f"/stories/{ghost}/like"),
        ("put", f"/stories/{ghost}/save"),
        ("delete", f"/stories/{ghost}/save"),
    ]:
        assert getattr(client, method)(f"{API}{path}", headers=h).status_code == 404, path


def test_follow_edge_cases(client, me):
    h = me["headers"]
    assert client.delete(f"{API}/users/edge_bd/follow", headers=h).status_code == 400
    assert client.put(f"{API}/users/edge_bd/follow", headers=h).status_code == 400
    assert client.delete(f"{API}/users/ghost_user/follow", headers=h).status_code == 404
    assert client.get(f"{API}/users/ghost_user/followers", headers=h).status_code == 404
    assert client.get(f"{API}/users/ghost_user/following", headers=h).status_code == 404


# --- authentication edge cases ----------------------------------------------------


def _token(**claims):
    now = int(time.time())
    base = {"sub": str(uuid.uuid4()), "jti": uuid.uuid4().hex, "type": "access", "iat": now}
    base["exp"] = now + 600
    return jwt.encode(
        {**base, **claims}, "dev-only-insecure-secret-key-change-me-0123456789", algorithm="HS256"
    )


def test_tokens_with_bad_or_unknown_subjects_are_rejected(client, me):
    for token in (_token(sub="not-a-uuid"), _token()):  # malformed id; well-formed unknown user
        res = client.get(f"{API}/users/me", headers={"Authorization": f"Bearer {token}"})
        assert res.status_code == 401


def test_deactivated_accounts_lose_access_immediately(client, me, db):
    assert client.get(f"{API}/users/me", headers=me["headers"]).status_code == 200
    db.query(User).filter_by(username="edge_bd").one().is_active = False
    db.commit()
    assert client.get(f"{API}/users/me", headers=me["headers"]).status_code == 401
    login = client.post(
        f"{API}/auth/login", json={"identifier": "edge_bd", "password": "correct-horse-1"}
    )
    assert login.status_code == 401


def test_concurrent_duplicate_registration_is_a_409_not_a_500(client, me, monkeypatch):
    real = UserRepository.exists
    calls = {"n": 0}

    def exists_once_false(self, **kw):
        calls["n"] += 1
        return (False, False) if calls["n"] == 1 else real(self, **kw)

    monkeypatch.setattr(UserRepository, "exists", exists_once_false)
    res = client.post(
        f"{API}/auth/register",
        json={"email": "edge_bd@example.com", "username": "edge_bd", "password": "correct-horse-1"},
    )
    assert res.status_code == 409
    fields = {e["loc"][-1] for e in res.json()["detail"]}
    assert fields == {"email", "username"}


def test_failed_media_row_insert_does_not_leave_a_stored_file(client, me, storage, monkeypatch):
    def boom(self, asset):
        raise IntegrityError("insert", {}, Exception("db down"))

    monkeypatch.setattr(MediaRepository, "add", boom)
    quiet = TestClient(app, raise_server_exceptions=False)
    res = upload(quiet, me)
    assert res.status_code == 500
    assert not [p for p in storage.root.rglob("*") if p.is_file()]


def test_health_reports_database_state(client):
    ok = client.get(f"{API}/health")
    assert ok.status_code == 200 and ok.json()["database"] == "ok"


def test_empty_and_non_image_uploads_are_refused(client, me):
    assert upload(client, me, data=b"").status_code in (400, 415, 422)
    assert upload(client, me, data=b"GIF89a-not-allowed").status_code == 415
    assert upload(client, me, data=image_bytes("PNG")).status_code == 201
