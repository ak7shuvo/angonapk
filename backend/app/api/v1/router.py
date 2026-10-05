from fastapi import APIRouter

from app.api.v1 import auth, comments, explore, health, media, places, posts, stories, users

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(media.router)
api_router.include_router(posts.router)
api_router.include_router(comments.router)
api_router.include_router(stories.router)
api_router.include_router(places.router)
api_router.include_router(explore.router)

# Planned routers (added per phase): notifications, reports.
