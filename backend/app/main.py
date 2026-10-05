from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.exc import DataError
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.middleware import BodySizeLimitMiddleware, SecurityHeadersMiddleware
from app.storage.factory import build_storage
from app.storage.local import LocalStorage


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
    )
    # Middleware added last runs first (outermost): host check, then size limit,
    # then CORS, with security headers on every response.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,  # bearer tokens in a header, never cookies
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
        max_age=600,
    )
    app.add_middleware(
        BodySizeLimitMiddleware,
        default_limit=settings.max_request_body_bytes,
        upload_limit=settings.max_upload_bytes + 256 * 1024,  # multipart framing
    )
    app.add_middleware(SecurityHeadersMiddleware, hsts=settings.is_production)
    if settings.allowed_hosts:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.allowed_hosts)
    app.include_router(api_router)

    @app.exception_handler(DataError)
    async def _bad_data(_: Request, __: DataError) -> JSONResponse:
        # The database refused a value (e.g. a NUL byte, which PostgreSQL text
        # cannot hold). That is the caller's input, not a server fault.
        return JSONResponse({"detail": "Request contains invalid characters"}, status_code=422)

    if not settings.is_production:
        storage = build_storage(settings)
        if isinstance(storage, LocalStorage):
            # Development only: serve locally stored media (production uses object storage/CDN).
            app.mount("/media", StaticFiles(directory=storage.root), name="media")
    return app


app = create_app()
