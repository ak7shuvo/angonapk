from pydantic import BaseModel

from app.schemas.place import PlaceSummary
from app.schemas.post import PostRead
from app.schemas.story import StorySummary


class NearbyRead(BaseModel):
    """What is around a point: places by distance plus recent content documenting them."""

    places: list[PlaceSummary]
    posts: list[PostRead]
    stories: list[StorySummary]
