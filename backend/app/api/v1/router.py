from fastapi import APIRouter

from app.api.v1 import health

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(health.router)

# Planned routers (added per phase): auth, users, posts, stories, places,
# comments, follows, notifications, reports.
