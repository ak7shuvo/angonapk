import uuid

import pytest

from app.core.geo import haversine_km
from app.models import Place
from tests.helpers import API, PLACE, make_admin, make_user, upload_id


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


@pytest.fixture
def bob(client):
    return make_user(client, "bob_bd")


@pytest.fixture
def admin(client, db):
    return make_admin(client, db)


def add_place(db, name, lat, lng, division="Sylhet", district="Sylhet", **kw) -> Place:
    from app.core.text import slugify

    place = Place(
        name=name,
        slug=slugify(name),
        latitude=lat,
        longitude=lng,
        division=division,
        district=district,
        meta={"source": "test"},
        **kw,
    )
    db.add(place)
    db.commit()
    return place


# --- geo helper ----------------------------------------------------------------


def test_haversine_is_sane():
    assert haversine_km(0, 0, 0, 0) == 0
    dhaka_to_sylhet = haversine_km(23.8103, 90.4125, 24.8949, 91.8687)
    assert 190 < dhaka_to_sylhet < 215
    assert haversine_km(23.8, 90.4, 24.9, 91.9) == pytest.approx(
        haversine_km(24.9, 91.9, 23.8, 90.4)
    )


# --- admin create / update ----------------------------------------------------


def test_admin_can_create_and_update_place(client, admin):
    res = client.post(f"{API}/places", headers=admin["headers"], json=PLACE)
    assert res.status_code == 201
    place = res.json()
    assert place["slug"] == "jaflong" and place["name_local"] == "জাফলং"
    assert place["country"] == "Bangladesh" and place["upazila"] == "Gowainghat"
    assert (place["post_count"], place["story_count"]) == (0, 0)
    # same name → unique slug
    assert (
        client.post(f"{API}/places", headers=admin["headers"], json=PLACE).json()["slug"]
        == "jaflong-2"
    )

    res = client.patch(
        f"{API}/places/{place['id']}",
        headers=admin["headers"],
        json={"description": "Updated.", "metadata": {"coordinates": "approximate"}},
    )
    assert res.status_code == 200
    assert res.json()["description"] == "Updated." and res.json()["metadata"] == {
        "coordinates": "approximate"
    }
    assert (
        client.patch(
            f"{API}/places/{uuid.uuid4()}", headers=admin["headers"], json={"name": "Xx"}
        ).status_code
        == 404
    )


def test_normal_users_cannot_create_or_update_places(client, alice, db):
    place = add_place(db, "Sreemangal", 24.3065, 91.7296)
    assert client.post(f"{API}/places", headers=alice["headers"], json=PLACE).status_code == 403
    assert (
        client.patch(
            f"{API}/places/{place.id}", headers=alice["headers"], json={"name": "Hacked"}
        ).status_code
        == 403
    )
    assert client.post(f"{API}/places", json=PLACE).status_code == 401


@pytest.mark.parametrize(
    "override",
    [
        {"latitude": 91},
        {"longitude": -181},
        {"name": " "},
        {"name": "x" * 121},
        {"cover_url": "javascript:alert(1)"},
        {"unknown": 1},
    ],
)
def test_place_validation(client, admin, override):
    assert (
        client.post(
            f"{API}/places", headers=admin["headers"], json={**PLACE, **override}
        ).status_code
        == 422
    )


# --- list / search / filters -------------------------------------------------


@pytest.fixture
def bangladesh(db):
    return {
        "jaflong": add_place(db, "Jaflong", 25.165, 92.017, name_local="জাফলং"),
        "sreemangal": add_place(db, "Sreemangal", 24.3065, 91.7296, district="Moulvibazar"),
        "coxs": add_place(
            db, "Cox's Bazar", 21.4272, 92.0058, division="Chattogram", district="Cox's Bazar"
        ),
        "bandarban": add_place(
            db, "Bandarban", 22.1953, 92.2184, division="Chattogram", district="Bandarban"
        ),
    }


def names(res):
    return [p["name"] for p in res.json()["items"]]


def test_list_search_and_filters(client, alice, bangladesh):
    h = alice["headers"]
    res = client.get(f"{API}/places", headers=h)
    assert res.json()["total"] == 4
    assert names(res) == ["Bandarban", "Cox's Bazar", "Jaflong", "Sreemangal"]  # by name
    assert names(client.get(f"{API}/places", headers=h, params={"q": "jaf"})) == ["Jaflong"]
    assert names(client.get(f"{API}/places", headers=h, params={"q": "জাফ"})) == [
        "Jaflong"
    ]  # Bengali
    assert names(client.get(f"{API}/places", headers=h, params={"q": "moulvi"})) == [
        "Sreemangal"
    ]  # by district
    assert names(client.get(f"{API}/places", headers=h, params={"division": "chattogram"})) == [
        "Bandarban",
        "Cox's Bazar",
    ]
    assert names(client.get(f"{API}/places", headers=h, params={"district": "Bandarban"})) == [
        "Bandarban"
    ]
    # LIKE wildcards are literal, not patterns
    assert names(client.get(f"{API}/places", headers=h, params={"q": "%"})) == []
    assert names(client.get(f"{API}/places", headers=h, params={"q": "_"})) == []
    page = client.get(f"{API}/places", headers=h, params={"limit": 2, "offset": 2}).json()
    assert page["total"] == 4 and [p["name"] for p in page["items"]] == ["Jaflong", "Sreemangal"]
    assert client.get(f"{API}/places").status_code == 401


def test_bounding_box_and_nearby(client, alice, bangladesh):
    h = alice["headers"]
    sylhet_box = {"min_lat": 24, "max_lat": 26, "min_lng": 91, "max_lng": 93}
    assert names(client.get(f"{API}/places", headers=h, params=sylhet_box)) == [
        "Jaflong",
        "Sreemangal",
    ]
    near = client.get(
        f"{API}/places", headers=h, params={"near_lat": 25.0, "near_lng": 92.0, "radius_km": 400}
    ).json()
    assert [p["name"] for p in near["items"]][:2] == ["Jaflong", "Sreemangal"]
    assert near["items"][0]["distance_km"] < near["items"][1]["distance_km"]
    close = client.get(
        f"{API}/places", headers=h, params={"near_lat": 25.165, "near_lng": 92.017, "radius_km": 5}
    ).json()
    assert [p["name"] for p in close["items"]] == ["Jaflong"] and close["items"][0][
        "distance_km"
    ] == 0
    # partial parameter sets are rejected
    assert client.get(f"{API}/places", headers=h, params={"min_lat": 1}).status_code == 422
    assert client.get(f"{API}/places", headers=h, params={"near_lat": 1}).status_code == 422
    assert (
        client.get(
            f"{API}/places", headers=h, params={"radius_km": 9999, "near_lat": 1, "near_lng": 1}
        ).status_code
        == 422
    )


def test_place_detail_by_slug(client, alice, bangladesh):
    res = client.get(f"{API}/places/jaflong", headers=alice["headers"])
    assert res.status_code == 200
    assert res.json()["name_local"] == "জাফলং" and res.json()["metadata"] == {"source": "test"}
    assert client.get(f"{API}/places/JAFLONG", headers=alice["headers"]).status_code == 200
    assert client.get(f"{API}/places/nowhere", headers=alice["headers"]).status_code == 404
    assert client.get(f"{API}/places/jaflong").status_code == 401


# --- posts & stories at a place ----------------------------------------------


def test_post_at_a_place(client, alice, bob, bangladesh):
    place = bangladesh["jaflong"]
    res = client.post(
        f"{API}/posts",
        headers=alice["headers"],
        json={"body": "Stones everywhere", "place_id": str(place.id)},
    )
    assert res.status_code == 201
    post = res.json()
    assert post["place"] == {
        "id": str(place.id),
        "slug": "jaflong",
        "name": "Jaflong",
        "name_local": "জাফলং",
    }
    assert post["place_id"] == str(place.id)
    assert post["location_text"] == "Jaflong"  # filled from the place when none was typed
    typed = client.post(
        f"{API}/posts",
        headers=alice["headers"],
        json={"body": "x", "place_id": str(place.id), "location_text": "Lalakhal side"},
    ).json()
    assert typed["location_text"] == "Lalakhal side"
    client.post(f"{API}/posts", headers=bob["headers"], json={"body": "elsewhere"})
    feed = client.get(f"{API}/places/jaflong/posts", headers=bob["headers"]).json()
    assert {p["body"] for p in feed["items"]} == {"Stones everywhere", "x"}
    assert (
        client.get(f"{API}/places/sreemangal/posts", headers=bob["headers"]).json()["items"] == []
    )
    # unknown place on create
    assert (
        client.post(
            f"{API}/posts",
            headers=alice["headers"],
            json={"body": "x", "place_id": str(uuid.uuid4())},
        ).status_code
        == 422
    )


def test_story_at_a_place_and_place_counts(client, alice, bob, bangladesh):
    place = bangladesh["jaflong"]
    pub = client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={
            "title": "Stones",
            "content": "Text",
            "status": "published",
            "place_id": str(place.id),
        },
    )
    assert pub.status_code == 201 and pub.json()["place"]["slug"] == "jaflong"
    client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "Draft", "content": "Text", "place_id": str(place.id)},
    )
    stories = client.get(f"{API}/places/jaflong/stories", headers=bob["headers"]).json()["items"]
    assert [s["title"] for s in stories] == ["Stones"]  # drafts never appear
    client.post(
        f"{API}/posts", headers=alice["headers"], json={"body": "p", "place_id": str(place.id)}
    )
    detail = client.get(f"{API}/places/jaflong", headers=bob["headers"]).json()
    assert (detail["post_count"], detail["story_count"]) == (1, 1)
    listing = {
        p["slug"]: p for p in client.get(f"{API}/places", headers=bob["headers"]).json()["items"]
    }
    assert listing["jaflong"]["post_count"] == 1 and listing["sreemangal"]["post_count"] == 0
    # editing a story's place, including clearing it
    sid = pub.json()["id"]
    res = client.patch(
        f"{API}/stories/{sid}",
        headers=alice["headers"],
        json={"place_id": str(bangladesh["coxs"].id)},
    )
    assert res.json()["place"]["slug"] == "cox-s-bazar"
    assert (
        client.patch(
            f"{API}/stories/{sid}", headers=alice["headers"], json={"place_id": None}
        ).json()["place"]
        is None
    )
    assert (
        client.patch(
            f"{API}/stories/{sid}", headers=alice["headers"], json={"place_id": str(uuid.uuid4())}
        ).status_code
        == 422
    )


def test_place_photos_and_creators(client, alice, bob, bangladesh):
    place = bangladesh["jaflong"]
    for who, n in ((alice, 2), (bob, 1)):
        for _ in range(n):
            asset = upload_id(client, who)
            client.post(
                f"{API}/posts",
                headers=who["headers"],
                json={"media": [{"asset_id": asset}], "place_id": str(place.id)},
            )
    photos = client.get(
        f"{API}/places/jaflong/photos", headers=bob["headers"], params={"limit": 2}
    ).json()
    assert len(photos["items"]) == 2 and photos["next_cursor"]
    assert photos["items"][0]["url"].startswith("/media/u/") and photos["items"][0]["post_id"]
    more = client.get(
        f"{API}/places/jaflong/photos",
        headers=bob["headers"],
        params={"limit": 2, "cursor": photos["next_cursor"]},
    ).json()
    assert len(more["items"]) == 1 and more["next_cursor"] is None
    creators = client.get(f"{API}/places/jaflong/creators", headers=bob["headers"]).json()
    assert [c["username"] for c in creators] == ["alice_bd", "bob_bd"]  # most active first
    assert creators[1]["is_me"] is True
    assert client.get(f"{API}/places/sreemangal/creators", headers=bob["headers"]).json() == []
    assert (
        client.get(
            f"{API}/places/jaflong/photos", headers=bob["headers"], params={"cursor": "zz"}
        ).status_code
        == 422
    )


def test_profile_places_count_reflects_documented_places(client, alice, bob, bangladesh):
    for slug in ("jaflong", "coxs"):
        place = bangladesh[slug]
        client.post(
            f"{API}/posts", headers=alice["headers"], json={"body": "p", "place_id": str(place.id)}
        )
    client.post(
        f"{API}/posts",
        headers=alice["headers"],
        json={"body": "again", "place_id": str(bangladesh["jaflong"].id)},
    )
    assert (
        client.get(f"{API}/users/alice_bd", headers=bob["headers"]).json()["counts"]["places"] == 2
    )


def test_deleting_a_place_keeps_content(client, alice, bangladesh, db):
    if db.get_bind().dialect.name != "postgresql":
        pytest.skip(
            "ON DELETE SET NULL is enforced by PostgreSQL (SQLite has no FK enforcement here)"
        )
    place = bangladesh["jaflong"]
    body = {"body": "p", "place_id": str(place.id)}
    pid = client.post(f"{API}/posts", headers=alice["headers"], json=body).json()["id"]
    db.delete(place)
    db.commit()
    got = client.get(f"{API}/posts/{pid}", headers=alice["headers"])
    assert got.status_code == 200 and got.json()["place"] is None


def test_users_places_endpoint(client, alice, bob, bangladesh):
    for slug, n in (("jaflong", 2), ("coxs", 1)):
        for _ in range(n):
            client.post(
                f"{API}/posts",
                headers=alice["headers"],
                json={"body": "p", "place_id": str(bangladesh[slug].id)},
            )
    client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "S", "content": "x", "place_id": str(bangladesh["sreemangal"].id)},
    )  # a draft does not count
    res = client.get(f"{API}/users/alice_bd/places", headers=bob["headers"])
    assert [p["name"] for p in res.json()] == ["Jaflong", "Cox's Bazar"]
    assert client.get(f"{API}/users/bob_bd/places", headers=bob["headers"]).json() == []
    assert client.get(f"{API}/users/ghost/places", headers=bob["headers"]).status_code == 404
    assert client.get(f"{API}/users/alice_bd/places").status_code == 401
