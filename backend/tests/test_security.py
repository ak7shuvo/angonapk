import io
import os
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.api.deps import get_storage
from app.core.config import Settings, get_settings, production_problems
from app.core.rate_limit import RateLimiter, limiter
from app.main import app, create_app
from app.storage.local import LocalStorage
from tests.helpers import API, image_bytes, make_user, upload

PROD = dict(
    app_env="production",
    secret_key="x" * 48,
    database_url="postgresql+psycopg://svc:strong@db.internal/angon",
    cors_origins=["https://app.example"],
    storage_provider="s3",
    rate_limit_enabled=True,
)


# --- rate limiter -----------------------------------------------------------------


def test_sliding_window_allows_then_blocks_then_recovers():
    rl = RateLimiter()
    assert [rl.check("k", 3, 10, now=t) for t in (0, 1, 2)] == [0, 0, 0]
    wait = rl.check("k", 3, 10, now=3)
    assert 6.9 < wait <= 7.1  # first hit (t=0) expires at t=10
    assert rl.check("other", 3, 10, now=3) == 0  # keys are independent
    assert rl.check("k", 3, 10, now=10.5) == 0  # window slid


def test_limiter_memory_is_bounded(monkeypatch):
    rl = RateLimiter()
    for i in range(50_050):
        rl.check(f"k{i}", 1, 1, now=float(i) / 1000)
    assert len(rl._hits) < 50_050


@pytest.fixture
def limited(client):
    """The API with rate limiting switched on (tests normally run with it off)."""
    app.dependency_overrides[get_settings] = lambda: Settings(rate_limit_enabled=True)
    limiter.reset()
    yield client
    limiter.reset()
    app.dependency_overrides.pop(get_settings, None)


def register(client, name, **kw):
    return client.post(
        f"{API}/auth/register",
        json={"email": f"{name}@example.com", "username": name, "password": "correct-horse-1"},
        **kw,
    )


def test_login_is_limited_per_account(limited):
    register(limited, "victim_bd")
    bad = {"identifier": "victim_bd", "password": "wrong-password"}
    codes = [limited.post(f"{API}/auth/login", json=bad).status_code for _ in range(12)]
    assert codes[:10] == [401] * 10
    assert codes[10:] == [429, 429]
    blocked = limited.post(f"{API}/auth/login", json=bad)
    assert blocked.headers["retry-after"].isdigit()
    # Even the right password is refused while locked, but other accounts are unaffected.
    good = {"identifier": "victim_bd", "password": "correct-horse-1"}
    assert limited.post(f"{API}/auth/login", json=good).status_code == 429
    other = {"identifier": "someone_else", "password": "nope-nope-nope"}
    assert limited.post(f"{API}/auth/login", json=other).status_code == 401


def test_login_is_limited_per_ip(limited):
    codes = [
        limited.post(
            f"{API}/auth/login", json={"identifier": f"user_{i}", "password": "wrong-password"}
        ).status_code
        for i in range(24)
    ]
    assert codes.count(401) == 20 and codes.count(429) == 4


def test_registration_is_limited_per_ip(limited):
    codes = [register(limited, f"newbie_{i}").status_code for i in range(12)]
    assert codes[:10] == [201] * 10 and codes[10:] == [429, 429]


def test_user_writes_are_limited(limited):
    me = make_user(limited, "poster_bd")
    pid = limited.post(f"{API}/posts", headers=me["headers"], json={"body": "first"}).json()["id"]
    codes = [
        limited.post(
            f"{API}/posts/{pid}/comments", headers=me["headers"], json={"body": "hi"}
        ).status_code
        for _ in range(62)
    ]
    assert codes.count(201) == 60 and codes.count(429) == 2
    # The limit is per user, not global.
    friend = make_user(limited, "friend_bd")
    ok = limited.post(f"{API}/posts/{pid}/comments", headers=friend["headers"], json={"body": "yo"})
    assert ok.status_code == 201


def test_upload_and_report_limits(limited):
    me = make_user(limited, "uploader_bd")
    codes = [upload(limited, me).status_code for _ in range(62)]
    assert codes.count(201) == 60 and codes.count(429) == 2


# --- request size -----------------------------------------------------------------


def test_oversized_json_body_is_rejected_before_parsing(client):
    me = make_user(client, "big_bd")
    big = '{"body": "' + "a" * (1024 * 1024 + 10) + '"}'
    res = client.post(
        f"{API}/posts", headers={**me["headers"], "Content-Type": "application/json"}, content=big
    )
    assert res.status_code == 413


def test_streamed_body_without_content_length_is_also_capped(client):
    me = make_user(client, "stream_bd")

    def chunks():
        for _ in range(40):
            yield b"a" * (64 * 1024)  # 2.5 MiB total, no Content-Length header

    res = client.post(
        f"{API}/posts",
        headers={**me["headers"], "Content-Type": "application/json"},
        content=chunks(),
    )
    assert res.status_code == 413


def test_oversized_upload_is_rejected(client, monkeypatch):
    me = make_user(client, "huge_bd")
    settings = Settings(max_upload_bytes=50_000)
    app.dependency_overrides[get_settings] = lambda: settings
    try:
        noise = Image.frombytes("RGB", (300, 300), os.urandom(300 * 300 * 3))  # incompressible
        buf = io.BytesIO()
        noise.save(buf, "PNG")
        data = buf.getvalue()
        res = client.post(
            f"{API}/media", headers=me["headers"], files={"file": ("a.png", data, "image/png")}
        )
        assert res.status_code == 413
    finally:
        app.dependency_overrides.pop(get_settings, None)


def test_normal_requests_are_unaffected_by_the_limit(client):
    me = make_user(client, "normal_bd")
    assert upload(client, me).status_code == 201
    res = client.post(f"{API}/posts", headers=me["headers"], json={"body": "ok " * 500})
    assert res.status_code == 201


# --- headers and CORS ---------------------------------------------------------------


def test_security_headers_on_every_response(client):
    for res in (client.get(f"{API}/health"), client.get(f"{API}/posts")):
        assert res.headers["x-content-type-options"] == "nosniff"
        assert res.headers["x-frame-options"] == "DENY"
        assert res.headers["referrer-policy"] == "no-referrer"
        assert "strict-transport-security" not in res.headers  # only in production


def test_cors_allows_configured_origins_only(client):
    ok = client.options(
        f"{API}/posts",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type",
        },
    )
    assert ok.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert "access-control-allow-credentials" not in ok.headers
    bad = client.options(
        f"{API}/posts",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"},
    )
    assert "access-control-allow-origin" not in bad.headers


# --- production configuration ---------------------------------------------------------


def test_production_config_checks():
    assert production_problems(Settings(**PROD)) == []
    cases = {
        "SECRET_KEY": dict(secret_key="short"),
        "CORS_ORIGINS": dict(cors_origins=["*"]),
        "DATABASE_URL": dict(database_url="postgresql+psycopg://angon:angon@db/angon"),
        "STORAGE_PROVIDER": dict(storage_provider="local"),
        "RATE_LIMIT_ENABLED": dict(rate_limit_enabled=False),
    }
    for name, override in cases.items():
        problems = production_problems(Settings(**{**PROD, **override}))
        assert any(name in p for p in problems), (name, problems)


def test_get_settings_refuses_unsafe_production(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("SECRET_KEY", "x" * 48)
    get_settings.cache_clear()
    try:
        with pytest.raises(RuntimeError, match="Unsafe production configuration"):
            get_settings()  # still the dev database URL and local storage
    finally:
        monkeypatch.undo()
        get_settings.cache_clear()


def test_production_app_hides_docs_and_media_and_sends_hsts(monkeypatch):
    monkeypatch.setattr("app.main.get_settings", lambda: Settings(**PROD))
    prod = TestClient(create_app())
    assert prod.get("/docs").status_code == 404
    assert prod.get("/media/anything.png").status_code == 404
    assert "max-age" in prod.get("/api/v1/health").headers["strict-transport-security"]


def test_trusted_hosts_reject_unknown_host_header(monkeypatch):
    monkeypatch.setattr("app.main.get_settings", lambda: Settings(allowed_hosts=["api.example"]))
    guarded = TestClient(create_app(), base_url="http://api.example")
    assert guarded.get("/api/v1/health").status_code in (200, 503)
    assert guarded.get("/api/v1/health", headers={"Host": "evil.example"}).status_code == 400


# --- tokens -----------------------------------------------------------------------------


def _forge(secret="dev-only-insecure-secret-key-change-me-0123456789", **claims):
    now = int(time.time())
    base = {"sub": str(uuid.uuid4()), "jti": "x", "type": "access", "iat": now, "exp": now + 600}
    return jwt.encode({**base, **claims}, secret, algorithm="HS256")


def test_forged_and_malformed_tokens_are_rejected(client):
    me = make_user(client, "tokens_bd")
    uid = me["user"]["id"]

    def status(token):
        return client.get(
            f"{API}/users/me", headers={"Authorization": f"Bearer {token}"}
        ).status_code

    assert status(_forge(sub=uid, secret="y" * 48)) == 401  # wrong signature
    assert status(_forge(sub=uid, exp=int(time.time()) - 10)) == 401  # expired
    assert status(_forge(sub=uid, type="refresh")) == 401  # wrong type
    unsigned = jwt.encode(
        {"sub": uid, "jti": "x", "type": "access", "exp": int(time.time()) + 60},
        None,
        algorithm="none",
    )
    assert status(unsigned) == 401  # alg=none
    assert status("not.a.jwt") == 401
    assert status("") == 401


# --- injection and traversal -----------------------------------------------------------


INJECTIONS = ["' OR '1'='1", "'; DROP TABLE users; --", "%' --", "\\", "%", "_", "\x00", "a" * 400]


@pytest.mark.parametrize("payload", INJECTIONS)
def test_hostile_strings_never_break_queries(client, payload):
    me = make_user(client, "probe_bd")
    h = me["headers"]
    for path, params in [
        ("/search", {"q": payload}),
        ("/places", {"q": payload}),
        ("/posts", {"tag": payload}),
        ("/stories", {"tag": payload}),
    ]:
        res = client.get(f"{API}{path}", headers=h, params=params)
        assert res.status_code in (200, 422), (path, payload, res.text)
    login = client.post(f"{API}/auth/login", json={"identifier": payload or "x", "password": "x"})
    assert login.status_code in (401, 422)
    if payload.isprintable():  # control characters can't even be put in a URL path
        assert client.get(f"{API}/users/{payload}", headers=h).status_code in (404, 422)
    # The accounts table is intact and the user can still authenticate.
    assert client.get(f"{API}/users/me", headers=h).status_code == 200


def test_like_search_treats_wildcards_literally(client):
    me = make_user(client, "wild_bd")
    client.post(f"{API}/posts", headers=me["headers"], json={"body": "plain words here"})
    res = client.get(f"{API}/search", headers=me["headers"], params={"q": "%"})
    assert res.status_code == 200
    body = res.json()
    assert not body["posts"] and not body["places"] and not body["stories"]


def test_storage_blocks_path_traversal(tmp_path):
    store = LocalStorage(str(tmp_path / "root"))
    for key in ["../escape.txt", "a/../../escape.txt", "/etc/passwd"]:
        with pytest.raises(ValueError):
            store.save(key, b"x", "text/plain")
    assert not (tmp_path / "escape.txt").exists()
    store.save("ok/inside.txt", b"x", "text/plain")
    assert (tmp_path / "root" / "ok" / "inside.txt").exists()


def test_media_mount_does_not_serve_outside_the_upload_dir(client, storage, tmp_path):
    (tmp_path / "secret.txt").write_text("top secret")
    app.dependency_overrides[get_storage] = lambda: storage
    for url in ["/media/../secret.txt", "/media/%2e%2e/secret.txt", "/media/..%2fsecret.txt"]:
        res = client.get(url)
        assert res.status_code in (400, 404)
        assert "top secret" not in res.text


def test_uploaded_polyglots_are_reencoded_not_stored_verbatim(client):
    me = make_user(client, "poly_bd")
    payload = b"<?php echo 'pwned'; ?>"
    res = upload(client, me, data=image_bytes("PNG") + payload, name="shell.php.png")
    assert res.status_code == 201
    stored = res.json()["url"]
    assert not stored.endswith(".php")
    html = io.BytesIO(b"<script>alert(1)</script>")
    bad = client.post(
        f"{API}/media", headers=me["headers"], files={"file": ("x.png", html, "image/png")}
    )
    assert bad.status_code == 415
