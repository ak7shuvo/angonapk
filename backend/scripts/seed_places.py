"""DEVELOPMENT SEED DATA: places in Bangladesh.

Coordinates are approximate (rounded to ~0.01°), descriptions are neutral
placeholder text written for development, and every row is flagged
`metadata.seed = true`. None of this is verified, authoritative information.
"""

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.text import slugify
from app.models import Place

DISCLAIMER = "Development sample description — not verified information."

# name, local name, lat, lng, division, district, upazila, description
PLACES = [
    (
        "Sylhet",
        "সিলেট",
        24.89,
        91.87,
        "Sylhet",
        "Sylhet",
        "Sylhet Sadar",
        "A city in north-eastern Bangladesh, a base for exploring the surrounding hills, tea gardens and rivers.",
    ),
    (
        "Jaflong",
        "জাফলং",
        25.17,
        92.02,
        "Sylhet",
        "Sylhet",
        "Gowainghat",
        "A riverside area near the Meghalaya hills, known for its stone-strewn riverbed and views of the hills.",
    ),
    (
        "Sreemangal",
        "শ্রীমঙ্গল",
        24.31,
        91.73,
        "Sylhet",
        "Moulvibazar",
        "Sreemangal",
        "A town surrounded by tea estates and forest.",
    ),
    (
        "Ratargul Swamp Forest",
        "রাতারগুল",
        25.01,
        91.94,
        "Sylhet",
        "Sylhet",
        "Gowainghat",
        "A freshwater swamp forest explored by small boats.",
    ),
    (
        "Bichanakandi",
        "বিছনাকান্দি",
        25.15,
        92.01,
        "Sylhet",
        "Sylhet",
        "Gowainghat",
        "A stream-fed stone beach area close to the hills.",
    ),
    (
        "Tanguar Haor",
        "টাঙ্গুয়ার হাওর",
        25.13,
        91.07,
        "Sylhet",
        "Sunamganj",
        "Tahirpur",
        "A large wetland of seasonal lakes and villages.",
    ),
    (
        "Rajshahi",
        "রাজশাহী",
        24.37,
        88.60,
        "Rajshahi",
        "Rajshahi",
        "Boalia",
        "A city on the Padma River in the north-west.",
    ),
    (
        "Paharpur",
        "পাহাড়পুর",
        25.03,
        88.98,
        "Rajshahi",
        "Naogaon",
        "Badalgachhi",
        "An archaeological site of a historic Buddhist monastery complex.",
    ),
    (
        "Sonargaon",
        "সোনারগাঁও",
        23.65,
        90.60,
        "Dhaka",
        "Narayanganj",
        "Sonargaon",
        "A historic former capital area with old buildings and a folk-art museum.",
    ),
    (
        "Bandarban",
        "বান্দরবান",
        22.20,
        92.22,
        "Chattogram",
        "Bandarban",
        "Bandarban Sadar",
        "A hill district home to several indigenous communities.",
    ),
    (
        "Rangamati",
        "রাঙ্গামাটি",
        22.65,
        92.18,
        "Chattogram",
        "Rangamati",
        "Rangamati Sadar",
        "A hill town around a large lake.",
    ),
    (
        "Cox's Bazar",
        "কক্সবাজার",
        21.43,
        92.01,
        "Chattogram",
        "Cox's Bazar",
        "Cox's Bazar Sadar",
        "A coastal city with a very long sandy beach.",
    ),
]


def seed_places(db: Session, cover_urls: list[str] | None = None) -> dict[str, Place]:
    """Create (or refresh) the seed places. Returns them by slug."""
    out: dict[str, Place] = {}
    for i, (name, local, lat, lng, division, district, upazila, desc) in enumerate(PLACES):
        slug = slugify(name)
        place = db.scalar(select(Place).where(Place.slug == slug))
        if place is None:
            place = Place(slug=slug, name=name, latitude=lat, longitude=lng)
            db.add(place)
        place.name = name
        place.name_local = local
        place.latitude, place.longitude = lat, lng
        place.division, place.district, place.upazila = division, district, upazila
        place.country = "Bangladesh"
        place.description = f"{desc} {DISCLAIMER}"
        place.cover_url = cover_urls[i % len(cover_urls)] if cover_urls else None
        place.meta = {"seed": True, "coordinates": "approximate", "source": "development seed"}
        out[slug] = place
    db.flush()
    return out
