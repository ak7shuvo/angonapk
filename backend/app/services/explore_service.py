from datetime import UTC, datetime, timedelta

from app.models import User
from app.repositories.explore_repository import ExploreRepository
from app.repositories.place_repository import PlaceRepository
from app.repositories.social_repository import SocialRepository
from app.schemas.explore import CategoryRead, ExploreRead, SearchResults
from app.services.place_service import PlaceService
from app.services.post_service import PostService
from app.services.social_service import user_summary
from app.services.story_service import StoryService

# The Explore categories. They are ordinary tags with a curated label, so
# authors categorise content simply by tagging it.
CATEGORIES = [
    ("travel", "Travel"),
    ("culture", "Culture"),
    ("heritage", "Heritage"),
    ("nature", "Nature"),
    ("food", "Food"),
    ("photography", "Photography"),
    ("people", "People"),
]

TRENDING_WINDOW = timedelta(days=30)


class ExploreService:
    def __init__(
        self,
        repo: ExploreRepository,
        posts: PostService,
        stories: StoryService,
        places: PlaceService,
        place_repo: PlaceRepository,
        social: SocialRepository,
    ) -> None:
        self.repo = repo
        self.posts = posts
        self.stories = stories
        self.places = places
        self.place_repo = place_repo
        self.social = social

    def _user_cards(self, viewer: User, users: list[User]):
        followed = self.social.following_ids(viewer.id, [u.id for u in users])
        return [
            user_summary(u, is_following=u.id in followed, is_me=u.id == viewer.id) for u in users
        ]

    def explore(self, viewer: User) -> ExploreRead:
        counts = self.repo.category_counts([slug for slug, _ in CATEGORIES])
        since = datetime.now(UTC) - TRENDING_WINDOW
        return ExploreRead(
            categories=[
                CategoryRead(
                    slug=slug, label=label, post_count=counts[slug][0], story_count=counts[slug][1]
                )
                for slug, label in CATEGORIES
            ],
            trending_posts=self.posts.present(
                self.repo.trending_posts(since=since, limit=10), viewer
            ),
            featured_stories=self.stories.summaries(self.repo.featured_stories(6), viewer),
            popular_places=self.places.popular(8),
            creators=self._user_cards(viewer, self.repo.creators(exclude=viewer.id, limit=10)),
        )

    def search(self, viewer: User, q: str, kind: str, *, limit: int, offset: int) -> SearchResults:
        q = q.strip()
        out = SearchResults(query=q)
        if kind in ("all", "users"):
            out.users = self._user_cards(
                viewer, self.repo.search_users(q, limit=limit, offset=offset)
            )
        if kind in ("all", "stories"):
            out.stories = self.stories.summaries(
                self.repo.search_stories(q, limit=limit, offset=offset), viewer
            )
        if kind in ("all", "posts"):
            out.posts = self.posts.present(
                self.repo.search_posts(q, limit=limit, offset=offset), viewer
            )
        if kind in ("all", "places"):
            rows, _ = self.place_repo.search(q=q, limit=limit, offset=offset)
            out.places = self.places.summaries(rows)
        return out
