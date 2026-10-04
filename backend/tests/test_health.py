import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.db.session import get_db
from app.main import app
from app.storage.factory import build_storage
from app.storage.local import LocalStorage


def test_health_ok(client: TestClient) -> None:
    res = client.get("/api/v1/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok", "environment": "test", "database": "ok"}


def test_health_degraded_when_db_down(client: TestClient) -> None:
    class Broken(Session):
        def execute(self, *a, **k):
            raise RuntimeError("db down")

    app.dependency_overrides[get_db] = lambda: Broken()
    try:
        res = client.get("/api/v1/health")
    finally:
        app.dependency_overrides.clear()
    assert res.json()["status"] == "degraded"
    assert res.json()["database"] == "unavailable"


def test_cors_allows_configured_origin(client: TestClient) -> None:
    res = client.options(
        "/api/v1/health",
        headers={"Origin": "http://localhost:3000", "Access-Control-Request-Method": "GET"},
    )
    assert res.headers["access-control-allow-origin"] == "http://localhost:3000"


def test_cors_rejects_unknown_origin(client: TestClient) -> None:
    res = client.options(
        "/api/v1/health",
        headers={"Origin": "http://evil.example", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in res.headers


def test_cors_origins_parse_from_comma_string() -> None:
    assert Settings(cors_origins="http://a.test, http://b.test").cors_origins == [
        "http://a.test",
        "http://b.test",
    ]


def test_local_storage_roundtrip_and_traversal_guard(tmp_path) -> None:
    storage = LocalStorage(str(tmp_path))
    obj = storage.save("posts/1/a.jpg", b"data", "image/jpeg")
    assert obj.url == "/media/posts/1/a.jpg" and obj.size == 4
    assert (tmp_path / "posts/1/a.jpg").read_bytes() == b"data"
    storage.delete("posts/1/a.jpg")
    assert not (tmp_path / "posts/1/a.jpg").exists()
    with pytest.raises(ValueError):
        storage.save("../escape.txt", b"x", "text/plain")


def test_storage_factory_rejects_unknown_provider() -> None:
    with pytest.raises(ValueError):
        build_storage(Settings(storage_provider="nope"))
