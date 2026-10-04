import uuid

import pytest

from app.models import MediaAsset, Story, StoryMedia
from app.services.story_service import make_summary, slugify
from tests.helpers import API, make_user, upload, upload_id


@pytest.fixture
def alice(client):
    return make_user(client, "alice_bd")


@pytest.fixture
def bob(client):
    return make_user(client, "bob_bd")


def create(client, who, **body):
    body.setdefault("title", "Jaflong: Beyond the Tourist View")
    body.setdefault("content", "First paragraph about the stones.\n\nSecond paragraph.")
    return client.post(f"{API}/stories", headers=who["headers"], json=body)


def publish_new(client, who, **kw) -> dict:
    res = create(client, who, status="published", **kw)
    assert res.status_code == 201, res.text
    return res.json()


# --- helpers ---------------------------------------------------------------


def test_slugify_handles_english_bengali_and_junk():
    assert slugify("Jaflong: Beyond the Tourist View!") == "jaflong-beyond-the-tourist-view"
    bn = slugify("জাফলংয়ের গল্প")
    assert "জাফলংয়ের" in bn and " " not in bn
    assert slugify("!!!") == "story"
    assert len(slugify("a " * 100)) <= 60


def test_make_summary_skips_markup_and_images():
    content = "## Heading\n\n![x](asset:" + str(uuid.uuid4()) + ")\n\n> A quote here\n\nBody text."
    assert make_summary(content) == "Heading"
    assert make_summary("![x](asset:" + str(uuid.uuid4()) + ")") == ""
    assert make_summary("word " * 100).endswith("…")


# --- create / read ---------------------------------------------------------


def test_create_draft_is_private_to_author(client, alice, bob):
    res = create(client, alice, tags=["Culture", "#heritage"], location_text="Jaflong, Sylhet")
    assert res.status_code == 201
    story = res.json()
    assert story["status"] == "draft" and story["published_at"] is None
    assert story["slug"].startswith("jaflong-beyond-the-tourist-view-")
    assert story["tags"] == ["culture", "heritage"]
    assert story["reading_minutes"] == 1
    assert story["author"]["username"] == "alice_bd"
    assert story["summary"] == "First paragraph about the stones."
    for ref in (story["id"], story["slug"]):
        assert client.get(f"{API}/stories/{ref}", headers=alice["headers"]).status_code == 200
        assert client.get(f"{API}/stories/{ref}", headers=bob["headers"]).status_code == 404
    feed = client.get(f"{API}/stories", headers=bob["headers"]).json()
    assert feed["items"] == []


def test_publish_flow_and_public_read_by_slug(client, alice, bob):
    story = create(client, alice).json()
    res = client.post(f"{API}/stories/{story['id']}/publish", headers=alice["headers"])
    assert res.status_code == 200 and res.json()["status"] == "published"
    first_published = res.json()["published_at"]
    assert first_published
    got = client.get(f"{API}/stories/{story['slug']}", headers=bob["headers"])
    assert got.status_code == 200 and got.json()["content"].startswith("First paragraph")
    feed = client.get(f"{API}/stories", headers=bob["headers"]).json()["items"]
    assert [s["id"] for s in feed] == [story["id"]]
    assert "content" not in feed[0]  # lists carry summaries, not bodies

    # Unpublish hides it again; republishing keeps the original publication date.
    res = client.post(f"{API}/stories/{story['id']}/unpublish", headers=alice["headers"])
    assert res.json()["status"] == "draft"
    assert client.get(f"{API}/stories/{story['id']}", headers=bob["headers"]).status_code == 404
    again = client.post(f"{API}/stories/{story['id']}/publish", headers=alice["headers"]).json()
    assert again["published_at"] == first_published


def test_create_published_directly(client, alice):
    story = publish_new(client, alice)
    assert story["status"] == "published" and story["published_at"]


@pytest.mark.parametrize(
    "body",
    [
        {"title": "", "content": "text", "status": "published"},
        {"title": "T", "content": "   ", "status": "published"},
        {"title": "x" * 201},
        {"content": "x" * 50_001},
        {"tags": ["a"]},
        {"unknown": 1},
        {"status": "archived"},
    ],
)
def test_story_validation(client, alice, body):
    assert create(client, alice, **body).status_code == 422


def test_cannot_publish_empty_story(client, alice):
    story = create(client, alice, title="Only a title", content="").json()
    res = client.post(f"{API}/stories/{story['id']}/publish", headers=alice["headers"])
    assert res.status_code == 422


def test_drafts_may_be_blank_title(client, alice):
    res = create(client, alice, title="", content="")
    assert res.status_code == 201 and res.json()["slug"].startswith("story-")


def test_unique_slugs_for_same_title(client, alice):
    a = create(client, alice).json()["slug"]
    b = create(client, alice).json()["slug"]
    assert a != b


def test_stories_require_auth(client, alice):
    story = create(client, alice).json()
    assert client.get(f"{API}/stories").status_code == 401
    assert client.get(f"{API}/stories/{story['id']}").status_code == 401
    assert client.post(f"{API}/stories", json={"title": "x"}).status_code == 401
    assert client.delete(f"{API}/stories/{story['id']}").status_code == 401


# --- edit / delete / permissions -------------------------------------------


def test_edit_partial_fields_and_tags(client, alice):
    story = create(client, alice, tags=["food"]).json()
    res = client.patch(
        f"{API}/stories/{story['id']}",
        headers=alice["headers"],
        json={"title": "New title", "tags": ["nature", "travel"], "location_text": "Sylhet"},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["title"] == "New title" and body["tags"] == ["nature", "travel"]
    assert body["content"].startswith("First paragraph")  # untouched
    assert body["slug"] == story["slug"]  # links stay stable
    assert (
        client.patch(
            f"{API}/stories/{story['id']}", headers=alice["headers"], json={"location_text": None}
        ).json()["location_text"]
        is None
    )


def test_published_story_cannot_be_edited_into_emptiness(client, alice):
    story = publish_new(client, alice)
    res = client.patch(
        f"{API}/stories/{story['id']}", headers=alice["headers"], json={"content": " "}
    )
    assert res.status_code == 422


def test_only_the_author_can_modify(client, alice, bob):
    pub = publish_new(client, alice)
    draft = create(client, alice, title="Secret draft").json()
    h = bob["headers"]
    assert (
        client.patch(f"{API}/stories/{pub['id']}", headers=h, json={"title": "x"}).status_code
        == 403
    )
    assert client.post(f"{API}/stories/{pub['id']}/unpublish", headers=h).status_code == 403
    assert client.delete(f"{API}/stories/{pub['id']}", headers=h).status_code == 403
    # Someone else's draft does not even reveal that it exists.
    assert (
        client.patch(f"{API}/stories/{draft['id']}", headers=h, json={"title": "x"}).status_code
        == 404
    )
    assert client.post(f"{API}/stories/{draft['id']}/publish", headers=h).status_code == 404
    assert client.delete(f"{API}/stories/{draft['id']}", headers=h).status_code == 404
    assert (
        client.get(f"{API}/stories/{pub['id']}", headers=alice["headers"]).json()["title"]
        == pub["title"]
    )


def test_delete_story_removes_it_and_its_files(client, alice, db, storage):
    cover = upload_id(client, alice)
    inline = upload_id(client, alice)
    story = create(
        client,
        alice,
        cover_asset_id=cover,
        content=f"Intro.\n\n![A river](asset:{inline})\n\nOutro.",
    ).json()
    assert len(list(storage.root.rglob("*.png"))) == 2
    assert (
        client.delete(f"{API}/stories/{story['id']}", headers=alice["headers"]).status_code == 204
    )
    assert client.get(f"{API}/stories/{story['id']}", headers=alice["headers"]).status_code == 404
    assert db.query(Story).count() == 0 and db.query(StoryMedia).count() == 0
    assert db.query(MediaAsset).count() == 0
    assert list(storage.root.rglob("*.png")) == []


# --- media -----------------------------------------------------------------


def test_cover_and_inline_images(client, alice):
    cover = upload(client, alice).json()
    inline = upload(client, alice).json()
    story = create(
        client,
        alice,
        cover_asset_id=cover["id"],
        content=f"Intro.\n\n![A river](asset:{inline['id']})\n\nOutro.",
    ).json()
    assert story["cover"]["id"] == cover["id"] and story["cover"]["url"].startswith("/media/u/")
    assert [m["id"] for m in story["media"]] == [inline["id"]]
    assert story["summary"] == "Intro."


def test_story_media_rules(client, alice, bob):
    mine = upload_id(client, alice)
    theirs = upload_id(client, bob)
    # someone else's asset, unknown asset, cover reused inline, malformed token
    assert create(client, alice, cover_asset_id=theirs).status_code == 422
    assert create(client, alice, cover_asset_id=str(uuid.uuid4())).status_code == 422
    assert create(client, alice, content=f"![x](asset:{theirs})").status_code == 422
    assert (
        create(client, alice, cover_asset_id=mine, content=f"![x](asset:{mine})").status_code == 422
    )
    # an asset already used by a post cannot be reused
    client.post(f"{API}/posts", headers=alice["headers"], json={"media": [{"asset_id": mine}]})
    assert create(client, alice, cover_asset_id=mine).status_code == 422


def test_replace_cover_and_remove_inline_cleans_up(client, alice, db, storage):
    cover1, cover2, inline = (upload_id(client, alice) for _ in range(3))
    story = create(
        client, alice, cover_asset_id=cover1, content=f"Text.\n\n![x](asset:{inline})"
    ).json()
    res = client.patch(
        f"{API}/stories/{story['id']}",
        headers=alice["headers"],
        json={"cover_asset_id": cover2, "content": "Text only now."},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["cover"]["id"] == cover2 and body["media"] == []
    ids = {str(a.id) for a in db.query(MediaAsset)}
    assert ids == {cover2}  # replaced cover and removed inline image were deleted
    assert len(list(storage.root.rglob("*.png"))) == 1
    # removing the cover entirely
    res = client.patch(
        f"{API}/stories/{story['id']}", headers=alice["headers"], json={"cover_asset_id": None}
    )
    assert res.json()["cover"] is None
    assert db.query(MediaAsset).count() == 0


def test_keeping_existing_images_on_edit_is_allowed(client, alice):
    cover, inline = upload_id(client, alice), upload_id(client, alice)
    story = create(client, alice, cover_asset_id=cover, content=f"A\n\n![x](asset:{inline})").json()
    res = client.patch(
        f"{API}/stories/{story['id']}",
        headers=alice["headers"],
        json={"title": "Retitled", "content": f"B\n\n![x](asset:{inline})"},
    )
    assert res.status_code == 200
    assert res.json()["cover"]["id"] == cover and len(res.json()["media"]) == 1


# --- feed / filters / mine -------------------------------------------------


def test_feed_pagination_filters_and_order(client, alice, bob):
    ids = [
        publish_new(client, alice, title=f"Story {i}", tags=["food" if i % 2 else "nature"])["id"]
        for i in range(5)
    ]
    other = publish_new(client, bob, title="Bob's story", tags=["food"])["id"]
    seen, cursor = [], None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        page = client.get(f"{API}/stories", headers=alice["headers"], params=params).json()
        seen += [s["id"] for s in page["items"]]
        cursor = page["next_cursor"]
        if not cursor:
            break
    assert seen == [other, *ids[::-1]]
    by_author = client.get(
        f"{API}/stories", headers=alice["headers"], params={"author": "bob_bd"}
    ).json()
    assert [s["id"] for s in by_author["items"]] == [other]
    by_tag = client.get(f"{API}/stories", headers=alice["headers"], params={"tag": "food"}).json()
    assert {s["id"] for s in by_tag["items"]} == {ids[1], ids[3], other}
    assert (
        client.get(f"{API}/stories", headers=alice["headers"], params={"author": "ghost"}).json()[
            "items"
        ]
        == []
    )
    assert (
        client.get(f"{API}/stories", headers=alice["headers"], params={"cursor": "zz"}).status_code
        == 422
    )


def test_mine_lists_drafts_and_published_with_filter(client, alice, bob):
    d = create(client, alice, title="Draft one").json()
    p = publish_new(client, alice, title="Pub one")
    create(client, bob, title="Bobs draft")
    allm = client.get(f"{API}/stories/mine", headers=alice["headers"]).json()["items"]
    assert {s["id"] for s in allm} == {d["id"], p["id"]}
    drafts = client.get(
        f"{API}/stories/mine", headers=alice["headers"], params={"status": "draft"}
    ).json()
    assert [s["id"] for s in drafts["items"]] == [d["id"]]
    pubs = client.get(
        f"{API}/stories/mine", headers=alice["headers"], params={"status": "published"}
    ).json()
    assert [s["id"] for s in pubs["items"]] == [p["id"]]
    assert (
        client.get(
            f"{API}/stories/mine", headers=alice["headers"], params={"status": "x"}
        ).status_code
        == 422
    )


# --- like / save / related -------------------------------------------------


def test_like_and_save_story(client, alice, bob):
    story = publish_new(client, alice)
    sid = story["id"]
    res = client.put(f"{API}/stories/{sid}/like", headers=bob["headers"])
    assert res.json() == {"liked": True, "like_count": 1}
    client.put(f"{API}/stories/{sid}/like", headers=bob["headers"])  # idempotent
    got = client.get(f"{API}/stories/{sid}", headers=bob["headers"]).json()
    assert got["like_count"] == 1 and got["liked_by_me"] is True and got["saved_by_me"] is False
    assert (
        client.get(f"{API}/stories/{sid}", headers=alice["headers"]).json()["liked_by_me"] is False
    )

    assert client.put(f"{API}/stories/{sid}/save", headers=bob["headers"]).status_code == 204
    saved = client.get(f"{API}/users/me/saved/stories", headers=bob["headers"]).json()["items"]
    assert [s["id"] for s in saved] == [sid] and saved[0]["saved_by_me"] is True
    client.delete(f"{API}/stories/{sid}/save", headers=bob["headers"])
    assert client.get(f"{API}/users/me/saved/stories", headers=bob["headers"]).json()["items"] == []
    assert (
        client.delete(f"{API}/stories/{sid}/like", headers=bob["headers"]).json()["like_count"] == 0
    )


def test_cannot_like_or_save_drafts_or_unknown(client, alice, bob):
    draft = create(client, alice).json()
    for url in (
        f"{API}/stories/{draft['id']}/like",
        f"{API}/stories/{uuid.uuid4()}/like",
        f"{API}/stories/{draft['id']}/save",
    ):
        assert client.put(url, headers=bob["headers"]).status_code == 404
    assert client.put(f"{API}/stories/{draft['id']}/like").status_code == 401


def test_related_stories_rank_by_shared_tags_and_author(client, alice, bob):
    main = publish_new(client, alice, title="Main", tags=["heritage", "culture"])
    two_tags = publish_new(client, bob, title="Two shared", tags=["heritage", "culture"])
    one_tag = publish_new(client, bob, title="One shared", tags=["culture"])
    same_author = publish_new(client, alice, title="Same author", tags=["food"])
    publish_new(client, bob, title="Unrelated", tags=["food"])
    create(client, bob, title="Draft with shared tags", tags=["heritage"])  # drafts never appear
    res = client.get(f"{API}/stories/{main['id']}/related", headers=bob["headers"])
    assert res.status_code == 200
    assert [s["id"] for s in res.json()] == [two_tags["id"], one_tag["id"], same_author["id"]]
    assert (
        client.get(
            f"{API}/stories/{main['id']}/related", headers=bob["headers"], params={"limit": 1}
        ).json()[0]["id"]
        == two_tags["id"]
    )
    assert (
        client.get(f"{API}/stories/{uuid.uuid4()}/related", headers=bob["headers"]).status_code
        == 404
    )


def test_story_reports_whether_viewer_follows_the_author(client, alice, bob):
    story = publish_new(client, alice)
    assert (
        client.get(f"{API}/stories/{story['id']}", headers=bob["headers"]).json()[
            "following_author"
        ]
        is False
    )
    client.put(f"{API}/users/alice_bd/follow", headers=bob["headers"])
    assert (
        client.get(f"{API}/stories/{story['id']}", headers=bob["headers"]).json()[
            "following_author"
        ]
        is True
    )
    feed = client.get(f"{API}/stories", headers=bob["headers"]).json()["items"]
    assert feed[0]["following_author"] is True


def test_bengali_story_roundtrip(client, alice):
    story = publish_new(
        client,
        alice,
        title="জাফলংয়ের গল্প",
        content="পাহাড় আর নদীর মিলনস্থল।\n\nদ্বিতীয় অনুচ্ছেদ।",
        tags=["ঐতিহ্য"],
    )
    got = client.get(f"{API}/stories/{story['slug']}", headers=alice["headers"]).json()
    assert got["title"] == "জাফলংয়ের গল্প" and got["tags"] == ["ঐতিহ্য"]
    assert got["summary"] == "পাহাড় আর নদীর মিলনস্থল।"
