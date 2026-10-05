import pytest

from app.models import Place
from tests.helpers import API, make_user


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


@pytest.fixture
def bob(client):
    return make_user(client, "bob_bd")


def complete(client, who, name, kind="storyteller"):
    client.patch(
        f"{API}/users/me/profile",
        headers=who["headers"],
        json={"display_name": name, "creator_type": kind},
    )


def post(client, who, body, **kw):
    res = client.post(f"{API}/posts", headers=who["headers"], json={"body": body, **kw})
    assert res.status_code == 201, res.text
    return res.json()["id"]


def story(client, who, title, content="Some text about it.", **kw):
    res = client.post(
        f"{API}/stories",
        headers=who["headers"],
        json={"title": title, "content": content, "status": "published", **kw},
    )
    assert res.status_code == 201, res.text
    return res.json()["id"]


def add_place(db, name, slug, local=None, district="Sylhet"):
    db.add(
        Place(
            name=name,
            slug=slug,
            name_local=local,
            latitude=25.0,
            longitude=92.0,
            division="Sylhet",
            district=district,
            meta={},
        )
    )
    db.commit()


# --- explore -----------------------------------------------------------------


def test_explore_requires_auth(client):
    assert client.get(f"{API}/explore").status_code == 401
    assert client.get(f"{API}/search", params={"q": "x"}).status_code == 401


def test_explore_on_an_empty_database(client, alice):
    body = client.get(f"{API}/explore", headers=alice["headers"]).json()
    assert [c["slug"] for c in body["categories"]] == [
        "travel",
        "culture",
        "heritage",
        "nature",
        "food",
        "photography",
        "people",
    ]
    assert body["categories"][0] == {
        "slug": "travel",
        "label": "Travel",
        "post_count": 0,
        "story_count": 0,
    }
    assert body["trending_posts"] == [] and body["featured_stories"] == []
    assert body["popular_places"] == [] and body["creators"] == []


def test_category_counts_use_tags(client, alice):
    post(client, alice, "a", tags=["food"])
    post(client, alice, "b", tags=["food", "culture"])
    story(client, alice, "S", tags=["food"])
    client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "D", "content": "x", "tags": ["food"]},
    )  # draft
    cats = {
        c["slug"]: c
        for c in client.get(f"{API}/explore", headers=alice["headers"]).json()["categories"]
    }
    assert (cats["food"]["post_count"], cats["food"]["story_count"]) == (2, 1)
    assert (cats["culture"]["post_count"], cats["culture"]["story_count"]) == (1, 0)
    assert cats["people"]["post_count"] == 0


def test_trending_posts_rank_by_real_engagement(client, alice, bob):
    quiet = post(client, alice, "quiet")
    liked = post(client, alice, "liked")
    discussed = post(client, alice, "discussed")
    newest = post(client, alice, "newest, no engagement")
    client.put(f"{API}/posts/{liked}/like", headers=bob["headers"])
    for _ in range(2):
        client.post(f"{API}/posts/{discussed}/comments", headers=bob["headers"], json={"body": "c"})
    ids = [
        p["id"]
        for p in client.get(f"{API}/explore", headers=alice["headers"]).json()["trending_posts"]
    ]
    # comments weigh more than likes; ties fall back to recency
    assert ids == [discussed, liked, newest, quiet]
    first = client.get(f"{API}/explore", headers=bob["headers"]).json()["trending_posts"][1]
    assert first["liked_by_me"] is True  # viewer-relative like everywhere


def test_featured_stories_prefer_liked_then_recent(client, alice, bob):
    old_liked = story(client, alice, "Liked story")
    recent = story(client, alice, "Recent story")
    client.put(f"{API}/stories/{old_liked}/like", headers=bob["headers"])
    ids = [
        s["id"]
        for s in client.get(f"{API}/explore", headers=bob["headers"]).json()["featured_stories"]
    ]
    assert ids == [old_liked, recent]


def test_creators_are_finished_profiles_ranked_by_followers(client, alice, bob):
    carol = make_user(client, "carol_bd")
    make_user(client, "dave_bd")  # never finished their profile
    complete(client, alice, "Alice", "photographer")
    complete(client, bob, "Bob", "guide")
    complete(client, carol, "Carol", "blogger")
    client.put(f"{API}/users/bob_bd/follow", headers=carol["headers"])
    client.put(f"{API}/users/bob_bd/follow", headers=alice["headers"])
    client.put(f"{API}/users/carol_bd/follow", headers=alice["headers"])
    cards = client.get(f"{API}/explore", headers=alice["headers"]).json()["creators"]
    assert [c["username"] for c in cards] == ["bob_bd", "carol_bd"]  # not me, not unfinished dave
    assert cards[0]["is_following"] is True and cards[0]["creator_type"] == "guide"


def test_popular_places_rank_by_content(client, alice, db):
    add_place(db, "Jaflong", "jaflong")
    add_place(db, "Sreemangal", "sreemangal")
    place = db.query(Place).filter_by(slug="sreemangal").one()
    post(client, alice, "tea", place_id=str(place.id))
    names = [
        p["name"]
        for p in client.get(f"{API}/explore", headers=alice["headers"]).json()["popular_places"]
    ]
    assert names == ["Sreemangal", "Jaflong"]


def test_posts_by_tag_for_category_pages(client, alice):
    post(client, alice, "about food", tags=["food"])
    post(client, alice, "about nature", tags=["nature"])
    res = client.get(f"{API}/posts", headers=alice["headers"], params={"tag": "#Food"})
    assert [p["body"] for p in res.json()["items"]] == ["about food"]
    assert (
        client.get(f"{API}/posts", headers=alice["headers"], params={"tag": "none"}).json()["items"]
        == []
    )


# --- search ------------------------------------------------------------------


def test_search_across_everything(client, alice, bob, db):
    complete(client, bob, "Nusrat Jahan")
    post(client, alice, "A morning in Jaflong with stones", tags=["nature"])
    post(client, alice, "unrelated")
    story(client, alice, "Jaflong, beyond the tourist view")
    story(client, alice, "Unrelated story")
    add_place(db, "Jaflong", "jaflong", local="জাফলং")
    add_place(db, "Sreemangal", "sreemangal")
    res = client.get(f"{API}/search", headers=alice["headers"], params={"q": "jaflong"}).json()
    assert res["query"] == "jaflong"
    assert [p["name"] for p in res["places"]] == ["Jaflong"]
    assert [s["title"] for s in res["stories"]] == ["Jaflong, beyond the tourist view"]
    assert [p["body"] for p in res["posts"]] == ["A morning in Jaflong with stones"]
    assert res["users"] == []
    people = client.get(f"{API}/search", headers=alice["headers"], params={"q": "nusrat"}).json()[
        "users"
    ]
    assert [u["username"] for u in people] == ["bob_bd"] and people[0][
        "display_name"
    ] == "Nusrat Jahan"


def test_search_bengali_and_tags(client, alice, db):
    post(client, alice, "জাফলংয়ে সকাল", tags=["ঐতিহ্য"])
    post(client, alice, "no match here", tags=["culture"])
    add_place(db, "Jaflong", "jaflong", local="জাফলং")
    res = client.get(f"{API}/search", headers=alice["headers"], params={"q": "জাফলং"}).json()
    assert [p["name"] for p in res["places"]] == ["Jaflong"]
    assert [p["body"] for p in res["posts"]] == ["জাফলংয়ে সকাল"]
    by_tag = client.get(
        f"{API}/search", headers=alice["headers"], params={"q": "#culture", "type": "posts"}
    ).json()
    assert [p["body"] for p in by_tag["posts"]] == ["no match here"]


def test_search_type_filter_limit_and_paging(client, alice):
    for i in range(5):
        post(client, alice, f"haor memories {i}")
    story(client, alice, "A haor story")
    res = client.get(
        f"{API}/search", headers=alice["headers"], params={"q": "haor", "type": "posts", "limit": 2}
    ).json()
    assert len(res["posts"]) == 2 and res["stories"] == [] and res["users"] == []
    nxt = client.get(
        f"{API}/search",
        headers=alice["headers"],
        params={"q": "haor", "type": "posts", "limit": 2, "offset": 2},
    ).json()
    assert [p["body"] for p in res["posts"] + nxt["posts"]] == [
        f"haor memories {i}" for i in (4, 3, 2, 1)
    ]
    allres = client.get(
        f"{API}/search", headers=alice["headers"], params={"q": "haor", "limit": 3}
    ).json()
    assert len(allres["posts"]) == 3 and len(allres["stories"]) == 1


def test_search_ranks_exact_username_first(client, alice):
    make_user(client, "rahim")
    make_user(client, "rahim_khan")
    make_user(client, "abdul_rahim")
    names = [
        u["username"]
        for u in client.get(
            f"{API}/search", headers=alice["headers"], params={"q": "rahim"}
        ).json()["users"]
    ]
    assert names == ["rahim", "rahim_khan", "abdul_rahim"]  # exact, prefix, contains


def test_search_hides_drafts_and_treats_wildcards_literally(client, alice):
    client.post(
        f"{API}/stories",
        headers=alice["headers"],
        json={"title": "Secret draft haor", "content": "x"},
    )
    post(client, alice, "100% real")
    post(client, alice, "100 pieces")
    assert (
        client.get(f"{API}/search", headers=alice["headers"], params={"q": "secret"}).json()[
            "stories"
        ]
        == []
    )
    res = client.get(
        f"{API}/search", headers=alice["headers"], params={"q": "%", "type": "posts"}
    ).json()
    assert [p["body"] for p in res["posts"]] == ["100% real"]
    assert (
        client.get(
            f"{API}/search", headers=alice["headers"], params={"q": "_", "type": "posts"}
        ).json()["posts"]
        == []
    )


@pytest.mark.parametrize(
    "params",
    [
        {},
        {"q": ""},
        {"q": "x" * 81},
        {"q": "a", "type": "nope"},
        {"q": "a", "limit": 0},
        {"q": "a", "limit": 31},
    ],
)
def test_search_validation(client, alice, params):
    assert client.get(f"{API}/search", headers=alice["headers"], params=params).status_code == 422


def test_blank_query_returns_nothing(client, alice):
    res = client.get(f"{API}/search", headers=alice["headers"], params={"q": "   "})
    assert res.status_code == 200 and res.json()["users"] == [] and res.json()["posts"] == []


def test_search_results_are_viewer_relative(client, alice, bob):
    pid = post(client, alice, "findable text")
    client.put(f"{API}/posts/{pid}/like", headers=bob["headers"])
    res = client.get(
        f"{API}/search", headers=bob["headers"], params={"q": "findable", "type": "posts"}
    ).json()
    assert res["posts"][0]["liked_by_me"] is True and res["posts"][0]["like_count"] == 1
