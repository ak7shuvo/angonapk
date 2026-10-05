from datetime import UTC, datetime, timedelta

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.security import InvalidTokenError, decode_access_token, hash_password, verify_password

API = "/api/v1"
GOOD = {"email": "Rahim@Example.com", "username": "Rahim_BD", "password": "correct-horse-1"}


def register(client: TestClient, **overrides):
    return client.post(f"{API}/auth/register", json={**GOOD, **overrides})


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def token(client: TestClient) -> str:
    return register(client).json()["access_token"]


# --- registration -----------------------------------------------------------


def test_register_creates_user_with_empty_profile(client):
    res = register(client)
    assert res.status_code == 201
    body = res.json()
    assert body["token_type"] == "bearer" and body["access_token"]
    user = body["user"]
    assert user["email"] == "rahim@example.com"  # normalised
    assert user["username"] == "rahim_bd"
    assert user["role"] == "user"
    assert "password" not in user and "password_hash" not in user
    assert user["profile"] == {
        "display_name": None,
        "bio": None,
        "location": None,
        "creator_type": None,
        "avatar_url": None,
        "cover_url": None,
        "is_complete": False,
    }


def test_password_is_hashed_in_db(client, db):
    from app.models import User

    register(client)
    stored = db.query(User).one().password_hash
    assert stored != GOOD["password"] and stored.startswith("$argon2")
    assert verify_password(GOOD["password"], stored)


@pytest.mark.parametrize(
    "override",
    [
        {"email": "not-an-email"},
        {"username": "ab"},
        {"username": "has space"},
        {"username": "bad-dash"},
        {"password": "short"},
        {"password": "x" * 129},
    ],
)
def test_register_validation(client, override):
    assert register(client, **override).status_code == 422


def test_duplicate_email_rejected_case_insensitively(client):
    assert register(client).status_code == 201
    res = register(client, email="RAHIM@example.com", username="someone_else")
    assert res.status_code == 409
    assert res.json()["detail"][0]["loc"] == ["body", "email"]


def test_duplicate_username_rejected_case_insensitively(client):
    assert register(client).status_code == 201
    res = register(client, email="other@example.com", username="RAHIM_bd")
    assert res.status_code == 409
    assert res.json()["detail"][0]["loc"] == ["body", "username"]


# --- login ------------------------------------------------------------------


def test_login_with_email_and_username(client):
    register(client)
    for identifier in ("rahim@example.com", "RAHIM@EXAMPLE.COM", "rahim_bd"):
        res = client.post(
            f"{API}/auth/login", json={"identifier": identifier, "password": GOOD["password"]}
        )
        assert res.status_code == 200, identifier
        assert res.json()["user"]["username"] == "rahim_bd"


def test_login_wrong_password(client):
    register(client)
    res = client.post(f"{API}/auth/login", json={"identifier": "rahim_bd", "password": "nope-nope"})
    assert res.status_code == 401
    assert res.headers["www-authenticate"] == "Bearer"


def test_login_unknown_user_has_same_error_as_wrong_password(client):
    register(client)
    bad_pw = client.post(
        f"{API}/auth/login", json={"identifier": "rahim_bd", "password": "wrong-pw"}
    )
    unknown = client.post(f"{API}/auth/login", json={"identifier": "ghost", "password": "wrong-pw"})
    assert unknown.status_code == bad_pw.status_code == 401
    assert unknown.json() == bad_pw.json()


def test_login_inactive_user_rejected(client, db):
    from app.models import User

    register(client)
    user = db.query(User).one()
    user.is_active = False
    db.commit()
    res = client.post(
        f"{API}/auth/login", json={"identifier": "rahim_bd", "password": GOOD["password"]}
    )
    assert res.status_code == 401


# --- JWT --------------------------------------------------------------------


def test_token_claims(token):
    payload = decode_access_token(token, get_settings())
    assert payload["type"] == "access" and payload["sub"] and payload["jti"]


def _forge(client_token: str, **changes) -> str:
    settings = get_settings()
    payload = decode_access_token(client_token, settings)
    payload.update(changes)
    return jwt.encode(payload, settings.secret_key, algorithm=settings.jwt_algorithm)


def test_expired_token_rejected(client, token):
    expired = _forge(token, exp=datetime.now(UTC) - timedelta(minutes=1))
    assert client.get(f"{API}/users/me", headers=auth_header(expired)).status_code == 401


def test_token_signed_with_wrong_key_rejected(client, token):
    payload = decode_access_token(token, get_settings())
    forged = jwt.encode(payload, "x" * 40, algorithm="HS256")
    assert client.get(f"{API}/users/me", headers=auth_header(forged)).status_code == 401


def test_alg_none_token_rejected(client, token):
    payload = decode_access_token(token, get_settings())
    forged = jwt.encode(payload, None, algorithm="none")
    assert client.get(f"{API}/users/me", headers=auth_header(forged)).status_code == 401


def test_wrong_token_type_rejected(client, token):
    refresh_like = _forge(token, type="refresh")
    assert client.get(f"{API}/users/me", headers=auth_header(refresh_like)).status_code == 401
    with pytest.raises(InvalidTokenError):
        decode_access_token(refresh_like, get_settings())


def test_token_for_deleted_user_rejected(client, db, token):
    from app.models import User

    db.delete(db.query(User).one())
    db.commit()
    assert client.get(f"{API}/users/me", headers=auth_header(token)).status_code == 401


def test_verify_password_handles_garbage_hash():
    assert verify_password("x", "not-a-hash") is False
    assert verify_password("x", None) is False
    assert verify_password("pw", hash_password("pw")) is True


# --- current user / unauthorized -------------------------------------------


def test_me_returns_current_user(client, token):
    res = client.get(f"{API}/users/me", headers=auth_header(token))
    assert res.status_code == 200
    assert res.json()["username"] == "rahim_bd"


def test_me_requires_authentication(client):
    assert client.get(f"{API}/users/me").status_code == 401
    assert (
        client.get(f"{API}/users/me", headers={"Authorization": "Bearer junk"}).status_code == 401
    )
    assert client.get(f"{API}/users/me", headers={"Authorization": "Basic abc"}).status_code == 401
    assert client.patch(f"{API}/users/me/profile", json={"bio": "x"}).status_code == 401
    assert client.post(f"{API}/auth/logout").status_code == 401


def test_tokens_are_per_user(client):
    t1 = register(client).json()["access_token"]
    t2 = register(client, email="b@example.com", username="user_b").json()["access_token"]
    assert client.get(f"{API}/users/me", headers=auth_header(t1)).json()["username"] == "rahim_bd"
    assert client.get(f"{API}/users/me", headers=auth_header(t2)).json()["username"] == "user_b"


# --- logout -----------------------------------------------------------------


def test_logout_revokes_only_that_token(client):
    register(client)
    login = lambda: client.post(  # noqa: E731
        f"{API}/auth/login", json={"identifier": "rahim_bd", "password": GOOD["password"]}
    ).json()["access_token"]
    t1, t2 = login(), login()
    assert client.post(f"{API}/auth/logout", headers=auth_header(t1)).status_code == 204
    assert client.get(f"{API}/users/me", headers=auth_header(t1)).status_code == 401
    assert client.get(f"{API}/users/me", headers=auth_header(t2)).status_code == 200
    # Reusing a revoked token to log out again is unauthorised, not an error.
    assert client.post(f"{API}/auth/logout", headers=auth_header(t1)).status_code == 401


# --- profile ----------------------------------------------------------------


def test_profile_setup_and_partial_update(client, token):
    h = auth_header(token)
    res = client.patch(
        f"{API}/users/me/profile",
        headers=h,
        json={
            "display_name": "  রহিম উদ্দিন  ",
            "creator_type": "photographer",
            "location": "Sylhet",
        },
    )
    assert res.status_code == 200
    profile = res.json()["profile"]
    assert profile["display_name"] == "রহিম উদ্দিন"  # trimmed, Bengali preserved
    assert profile["creator_type"] == "photographer"
    assert profile["is_complete"] is True

    res = client.patch(f"{API}/users/me/profile", headers=h, json={"bio": "Chasing haors."})
    profile = res.json()["profile"]
    assert profile["bio"] == "Chasing haors."
    assert profile["display_name"] == "রহিম উদ্দিন"  # untouched fields persist

    # Persisted, not just echoed.
    me = client.get(f"{API}/users/me", headers=h).json()["profile"]
    assert me["bio"] == "Chasing haors." and me["location"] == "Sylhet"


def test_profile_incomplete_without_creator_type(client, token):
    res = client.patch(
        f"{API}/users/me/profile", headers=auth_header(token), json={"display_name": "Rahim"}
    )
    assert res.json()["profile"]["is_complete"] is False


def test_profile_can_clear_optional_field(client, token):
    h = auth_header(token)
    client.patch(f"{API}/users/me/profile", headers=h, json={"bio": "hello"})
    res = client.patch(f"{API}/users/me/profile", headers=h, json={"bio": "   "})
    assert res.json()["profile"]["bio"] is None


@pytest.mark.parametrize(
    "body",
    [
        {"creator_type": "admin"},
        {"bio": "x" * 501},
        {"display_name": "x" * 81},
        {"role": "admin"},  # extra fields are rejected, no privilege escalation
        {"username": "hijack"},
    ],
)
def test_profile_validation(client, token, body):
    res = client.patch(f"{API}/users/me/profile", headers=auth_header(token), json=body)
    assert res.status_code == 422


def test_cannot_modify_another_users_profile(client):
    t1 = register(client).json()["access_token"]
    t2 = register(client, email="b@example.com", username="user_b").json()["access_token"]
    client.patch(f"{API}/users/me/profile", headers=auth_header(t1), json={"bio": "mine"})
    me2 = client.get(f"{API}/users/me", headers=auth_header(t2)).json()
    assert me2["profile"]["bio"] is None
