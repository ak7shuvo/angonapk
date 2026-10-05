from pydantic import BaseModel

from app.schemas.place import PlaceSummary
from app.schemas.post import PostRead
from app.schemas.social import UserSummary
from app.schemas.story import StorySummary


class CategoryRead(BaseModel):
    slug: str
    label: str
    post_count: int
    story_count: int


class ExploreRead(BaseModel):
    categories: list[CategoryRead]
    trending_posts: list[PostRead]
    featured_stories: list[StorySummary]
    popular_places: list[PlaceSummary]
    creators: list[UserSummary]


class SearchResults(BaseModel):
    query: str
    users: list[UserSummary] = []
    stories: list[StorySummary] = []
    posts: list[PostRead] = []
    places: list[PlaceSummary] = []
