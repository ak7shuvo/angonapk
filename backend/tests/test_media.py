import io
import uuid
from datetime import timedelta

import pytest
from PIL import Image

from app.core.config import get_settings
from app.models import MediaAsset
from app.services.media_service import MediaService
from tests.helpers import API, image_bytes, make_user, upload, upload_id


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


@pytest.fixture
def bob(client):
    return make_user(client, "bob_bd")


def test_upload_requires_auth(client):
    res = client.post(f"{API}/media", files={"file": ("a.png", image_bytes(), "image/png")})
    assert res.status_code == 401


@pytest.mark.parametrize(
    "fmt,ctype", [("PNG", "image/png"), ("JPEG", "image/jpeg"), ("WEBP", "image/webp")]
)
def test_upload_valid_formats(client, alice, storage, fmt, ctype):
    res = upload(client, alice, data=image_bytes(fmt, (200, 100)), ctype=ctype)
    assert res.status_code == 201
    body = res.json()
    assert body["content_type"] == ctype
    assert (body["width"], body["height"]) == (200, 100)
    assert body["url"].startswith("/media/u/")
    # The URL is a public path, never a filesystem path, and the file exists in storage.
    assert str(storage.root) not in body["url"]
    key = body["url"].removeprefix("/media/")
    assert (storage.root / key).exists()


def test_client_filename_is_never_used_in_storage_key(client, alice, storage):
    res = upload(client, alice, name="../../etc/passwd.png")
    assert res.status_code == 201
    assert "passwd" not in res.json()["url"] and ".." not in res.json()["url"]


def test_upload_rejects_non_image_with_image_content_type(client, alice):
    res = upload(
        client, alice, data=b"<html>not an image</html>", name="evil.png", ctype="image/png"
    )
    assert res.status_code == 415


def test_upload_rejects_unsupported_format(client, alice):
    res = upload(client, alice, data=image_bytes("GIF"), name="a.gif", ctype="image/gif")
    assert res.status_code == 415
    res = upload(client, alice, data=image_bytes("BMP"), name="a.bmp", ctype="image/bmp")
    assert res.status_code == 415


def test_upload_rejects_empty_and_truncated(client, alice):
    assert upload(client, alice, data=b"").status_code == 415
    assert upload(client, alice, data=image_bytes()[:30]).status_code == 415


def test_upload_rejects_too_large(client, alice, monkeypatch):
    monkeypatch.setattr(get_settings(), "max_upload_bytes", 1000)
    big = image_bytes("PNG", (400, 400))
    assert len(big) > 1000
    assert upload(client, alice, data=big).status_code == 413


def test_oversized_images_are_downscaled_and_metadata_stripped(client, alice, storage, monkeypatch):
    monkeypatch.setattr(get_settings(), "max_image_edge", 128)
    img = Image.new("RGB", (400, 200), "red")
    exif = Image.Exif()
    exif[0x010F] = "SecretCamera"  # Make
    out = io.BytesIO()
    img.save(out, "JPEG", exif=exif)
    res = upload(client, alice, data=out.getvalue(), ctype="image/jpeg").json()
    assert (res["width"], res["height"]) == (128, 64)
    stored = Image.open(storage.root / res["url"].removeprefix("/media/"))
    assert not stored.getexif()  # EXIF (incl. GPS) removed


def test_decompression_bomb_rejected(client, alice, monkeypatch):
    monkeypatch.setattr(get_settings(), "max_image_pixels", 1000)
    assert upload(client, alice, data=image_bytes("PNG", (200, 200))).status_code == 415


def test_delete_unattached_media(client, alice, bob, storage):
    asset = upload(client, alice).json()
    path = storage.root / asset["url"].removeprefix("/media/")
    assert client.delete(f"{API}/media/{asset['id']}", headers=bob["headers"]).status_code == 404
    assert path.exists()
    assert client.delete(f"{API}/media/{asset['id']}", headers=alice["headers"]).status_code == 204
    assert not path.exists()
    assert client.delete(f"{API}/media/{asset['id']}", headers=alice["headers"]).status_code == 404


def test_cannot_delete_attached_media(client, alice):
    asset = upload_id(client, alice)
    client.post(f"{API}/posts", headers=alice["headers"], json={"media": [{"asset_id": asset}]})
    assert client.delete(f"{API}/media/{asset}", headers=alice["headers"]).status_code == 409


def test_cannot_attach_someone_elses_or_unknown_or_reused_media(client, alice, bob):
    mine = upload_id(client, alice)
    h = bob["headers"]
    assert (
        client.post(f"{API}/posts", headers=h, json={"media": [{"asset_id": mine}]}).status_code
        == 422
    )
    unknown = {"media": [{"asset_id": str(uuid.uuid4())}]}
    assert client.post(f"{API}/posts", headers=h, json=unknown).status_code == 422
    ok = client.post(f"{API}/posts", headers=alice["headers"], json={"media": [{"asset_id": mine}]})
    assert ok.status_code == 201
    again = client.post(
        f"{API}/posts", headers=alice["headers"], json={"media": [{"asset_id": mine}]}
    )
    assert again.status_code == 422  # one asset, one use
    dup = client.post(
        f"{API}/posts",
        headers=alice["headers"],
        json={"media": [{"asset_id": mine}, {"asset_id": mine}]},
    )
    assert dup.status_code == 422


def test_failed_post_creation_keeps_uploaded_media_for_retry(client, alice, db):
    asset = upload_id(client, alice)
    res = client.post(
        f"{API}/posts",
        headers=alice["headers"],
        json={"media": [{"asset_id": asset}], "tags": ["x"]},
    )
    assert res.status_code == 422
    assert db.get(MediaAsset, uuid.UUID(asset)) is not None


def test_orphan_cleanup_removes_only_old_unattached_assets(client, alice, db, storage):
    from app.repositories.media_repository import MediaRepository

    settings = get_settings()
    orphan = upload(client, alice).json()
    attached = upload_id(client, alice)
    client.post(f"{API}/posts", headers=alice["headers"], json={"media": [{"asset_id": attached}]})
    svc = MediaService(MediaRepository(db), storage, settings)
    assert svc.cleanup_orphans(older_than=timedelta(hours=24)) == 0  # too recent
    assert svc.cleanup_orphans(older_than=timedelta(seconds=-1)) == 1
    assert db.get(MediaAsset, uuid.UUID(orphan["id"])) is None
    assert db.get(MediaAsset, uuid.UUID(attached)) is not None
