import pytest

from app.core.text import slugify
from app.models import Place
from tests.helpers import API, make_user


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


def add(db, name, lat, lng) -> Place:
    place = Place(name=name, slug=slugify(name), latitude=lat, longitude=lng, division="X", meta={})
    db.add(place)
    db.commit()
    return place


@pytest.fixture
def world(db):
    return {
        "jaflong": add(db, "Jaflong", 25.165, 92.017),
        "bichanakandi": add(db, "Bichanakandi", 25.15, 92.01),  # ~2 km from Jaflong
        "sreemangal": add(db, "Sreemangal", 24.3065, 91.7296),  # ~100 km away
        "coxs": add(db, "Cox's Bazar", 21.4272, 92.0058),  # ~400 km away
    }


def nearby(client, who, **params):
    return client.get(f"{API}/map/nearby", headers=who["headers"], params=params)


def test_requires_auth_and_valid_params(client, alice):
    assert client.get(f"{API}/map/nearby", params={"lat": 1, "lng": 1}).status_code == 401
    for params in (
        {},
        {"lat": 1},
        {"lat": 91, "lng": 0},
        {"lat": 0, "lng": 181},
        {"lat": 0, "lng": 0, "radius_km": 0},
        {"lat": 0, "lng": 0, "radius_km": 201},
        {"lat": 0, "lng": 0, "limit": 21},
    ):
        assert nearby(client, alice, **params).status_code == 422


def test_nearby_places_are_sorted_by_distance_within_radius(client, alice, world):
    res = nearby(client, alice, lat=25.165, lng=92.017, radius_km=10).json()
    assert [p["name"] for p in res["places"]] == ["Jaflong", "Bichanakandi"]
    assert res["places"][0]["distance_km"] == 0 and 0 < res["places"][1]["distance_km"] < 5
    wider = nearby(client, alice, lat=25.165, lng=92.017, radius_km=150).json()
    assert [p["name"] for p in wider["places"]] == ["Jaflong", "Bichanakandi", "Sreemangal"]
    assert nearby(client, alice, lat=0, lng=0).json() == {"places": [], "posts": [], "stories": []}


def test_nearby_content_comes_only_from_nearby_places(client, alice, world):
    def post(body, place):
        client.post(
            f"{API}/posts", headers=alice["headers"], json={"body": body, "place_id": str(place.id)}
        )

    post("near one", world["jaflong"])
    post("near two", world["bichanakandi"])
    post("far away", world["coxs"])
    post("sylhet tea", world["sreemangal"])
    client.post(f"{API}/posts", headers=alice["headers"], json={"body": "no place"})
    client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={
            "title": "Nearby story",
            "content": "x",
            "status": "published",
            "place_id": str(world["jaflong"].id),
        },
    )
    client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "Draft story", "content": "x", "place_id": str(world["jaflong"].id)},
    )
    res = nearby(client, alice, lat=25.165, lng=92.017, radius_km=10).json()
    assert [p["body"] for p in res["posts"]] == ["near two", "near one"]  # newest first
    assert [s["title"] for s in res["stories"]] == ["Nearby story"]  # drafts excluded
    assert res["posts"][0]["place"]["slug"] == "bichanakandi"
    limited = nearby(client, alice, lat=25.165, lng=92.017, radius_km=10, limit=1).json()
    assert len(limited["posts"]) == 1
