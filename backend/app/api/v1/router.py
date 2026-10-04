from fastapi import APIRouter

from app.api.v1 import auth, comments, health, media, posts, users

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(media.router)
api_router.include_router(posts.router)
api_router.include_router(comments.router)

# Planned routers (added per phase): stories, places,
# comments, follows, notifications, reports.
