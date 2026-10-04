import io

from fastapi.testclient import TestClient
from PIL import Image

API = "/api/v1"


def image_bytes(fmt: str = "PNG", size: tuple[int, int] = (64, 48), color=(180, 83, 42)) -> bytes:
    out = io.BytesIO()
    Image.new("RGB", size, color).save(out, fmt)
    return out.getvalue()


def make_user(client: TestClient, username: str = "rahim_bd") -> dict:
    res = client.post(
        f"{API}/auth/register",
        json={
            "email": f"{username}@example.com",
            "username": username,
            "password": "correct-horse-1",
        },
    )
    assert res.status_code == 201, res.text
    body = res.json()
    return {"headers": {"Authorization": f"Bearer {body['access_token']}"}, "user": body["user"]}


def upload(
    client: TestClient, who: dict, data: bytes | None = None, name="a.png", ctype="image/png"
):
    res = client.post(
        f"{API}/media",
        headers=who["headers"],
        files={"file": (name, data if data is not None else image_bytes(), ctype)},
    )
    return res


def upload_id(client: TestClient, who: dict, **kw) -> str:
    res = upload(client, who, **kw)
    assert res.status_code == 201, res.text
    return res.json()["id"]
