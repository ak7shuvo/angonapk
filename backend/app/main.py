from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.storage.factory import build_storage
from app.storage.local import LocalStorage


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(api_router)
    if not settings.is_production:
        storage = build_storage(settings)
        if isinstance(storage, LocalStorage):
            # Development only: serve locally stored media (production uses object storage/CDN).
            app.mount("/media", StaticFiles(directory=storage.root), name="media")
    return app


app = create_app()
