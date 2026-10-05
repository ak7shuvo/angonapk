import pytest
from sqlalchemy.orm import sessionmaker

from tests.helpers import API


@pytest.fixture
def seeded(client, db_engine, monkeypatch, tmp_path):
    from app.core.config import get_settings
    from scripts import seed_dev

    monkeypatch.setenv("STORAGE_LOCAL_DIR", str(tmp_path / "seed-uploads"))
    get_settings.cache_clear()
    factory = sessionmaker(bind=db_engine, expire_on_commit=False)
    monkeypatch.setattr(seed_dev, "get_session_factory", lambda: factory)
    try:
        seed_dev.main()
        yield seed_dev
    finally:
        get_settings.cache_clear()


def login(client, seed) -> dict:
    res = client.post(
        f"{API}/auth/login", json={"identifier": "seed_rahim", "password": seed.SEED_PASSWORD}
    )
    return {"Authorization": f"Bearer {res.json()['access_token']}"}


def test_every_seed_creator_and_story_is_marked_as_sample_content(client, seeded):
    headers = login(client, seeded)
    stories = client.get(f"{API}/stories", headers=headers, params={"limit": 50}).json()["items"]
    assert len(stories) == len(seeded.SEED_STORIES)
    for story in stories:
        assert story["author"]["display_name"].startswith("[Seed]")
        full = client.get(f"{API}/stories/{story['id']}", headers=headers).json()
        assert "Development sample story" in full["content"]
        assert full["cover"] and full["place"]
    posts = client.get(f"{API}/posts", headers=headers, params={"limit": 50}).json()["items"]
    assert len(posts) == len(seeded.SEED_POSTS)
    assert all(p["author"]["display_name"].startswith("[Seed]") for p in posts)
    profile = client.get(f"{API}/users/seed_mitu", headers=headers).json()
    assert profile["bio"].startswith("[SEED DATA]")


def test_content_is_linked_to_all_twelve_places(client, seeded):
    headers = login(client, seeded)
    places = client.get(f"{API}/places", headers=headers, params={"limit": 50}).json()
    slugs = (
        {p["slug"] for p in places["items"]}
        if isinstance(places, dict)
        else {p["slug"] for p in places}
    )
    assert len(slugs) == 12
    linked = {p[3] for p in seeded.SEED_POSTS if p[3]} | {s[3] for s in seeded.SEED_STORIES}
    assert linked == slugs  # every place has at least one post or story
    jaflong = client.get(f"{API}/places/jaflong", headers=headers).json()
    assert jaflong["post_count"] >= 1 and jaflong["story_count"] >= 1
    posts = client.get(f"{API}/places/jaflong/posts", headers=headers).json()["items"]
    assert posts and all(p["place"]["slug"] == "jaflong" for p in posts)
    assert client.get(f"{API}/places/jaflong/creators", headers=headers).json()


def test_discovery_surfaces_the_seed_content(client, seeded):
    headers = login(client, seeded)
    explore = client.get(f"{API}/explore", headers=headers).json()
    assert all(c["post_count"] + c["story_count"] > 0 for c in explore["categories"])
    assert explore["featured_stories"] and explore["trending_posts"]
    found = client.get(f"{API}/search", headers=headers, params={"q": "জাফলং"}).json()
    assert found["places"] and (found["posts"] or found["stories"])
    near = client.get(
        f"{API}/map/nearby",
        headers=headers,
        params={"lat": 25.17, "lng": 92.02, "radius_km": 30},
    )
    assert near.status_code == 200 and near.json()["places"]


def test_only_the_owner_sees_the_seed_draft_and_rerunning_is_idempotent(
    client, seeded, db_engine, monkeypatch
):
    headers = login(client, seeded)
    mine = client.get(f"{API}/stories/mine", headers=headers, params={"status": "draft"}).json()
    assert [s["title"] for s in mine["items"]] == [seeded.SEED_DRAFT_TITLE]
    public = client.get(f"{API}/stories", headers=headers, params={"limit": 50}).json()["items"]
    assert seeded.SEED_DRAFT_TITLE not in [s["title"] for s in public]

    seeded.main()  # run again: replaces its own content, never duplicates
    posts = client.get(f"{API}/posts", headers=headers, params={"limit": 50}).json()["items"]
    stories = client.get(f"{API}/stories", headers=headers, params={"limit": 50}).json()["items"]
    assert (len(posts), len(stories)) == (len(seeded.SEED_POSTS), len(seeded.SEED_STORIES))


def test_seed_text_makes_no_factual_claims():
    """Guard rail: the sample text stays subjective (no digits, no 'UNESCO' style claims)."""
    from scripts.seed_content import SEED_POSTS, SEED_STORIES

    texts = [p[1] for p in SEED_POSTS] + [line for s in SEED_STORIES for line in s[7]]
    banned = ("unesco", "largest", "oldest", "century", "built in", "founded", "world heritage")
    for text in texts:
        low = text.lower()
        assert not any(word in low for word in banned), text
        assert not any(ch.isdigit() for ch in text), text
