from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEV_SECRET = "dev-only-insecure-secret-key-change-me-0123456789"


class Settings(BaseSettings):
    """Application settings, loaded from environment variables / `.env`."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "ANGON API"
    app_env: str = "development"  # development | staging | production
    secret_key: str = _DEV_SECRET
    jwt_algorithm: str = "HS256"
    # No refresh tokens yet (see docs/API.md), so access tokens are long-lived.
    access_token_expire_minutes: int = 60 * 24 * 7
    database_url: str = "postgresql+psycopg://angon:angon@localhost:5432/angon"
    cors_origins: list[str] = ["http://localhost:3000"]
    # Hostnames the API answers to (Host header). Empty = no restriction.
    allowed_hosts: list[str] = []

    # Abuse protection (in-process; see app/core/rate_limit.py for its limits).
    rate_limit_enabled: bool = True
    max_request_body_bytes: int = 1024 * 1024  # JSON bodies; uploads use max_upload_bytes

    storage_provider: str = "local"
    storage_local_dir: str = "./var/uploads"

    # Uploads (images). Validated server-side regardless of what the client claims.
    max_upload_bytes: int = 10 * 1024 * 1024
    max_image_edge: int = 4096  # longest side after downscaling
    max_image_pixels: int = 60_000_000  # decompression-bomb guard

    @field_validator("cors_origins", "allowed_hosts", mode="before")
    @classmethod
    def _split_origins(cls, v):
        if isinstance(v, str):
            return [o.strip() for o in v.split(",") if o.strip()]
        return v

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    if settings.is_production:
        problems = production_problems(settings)
        if problems:
            raise RuntimeError("Unsafe production configuration: " + "; ".join(problems))
    return settings


def production_problems(settings: Settings) -> list[str]:
    """Settings that must never reach production. Checked at startup."""
    problems = []
    if settings.secret_key == _DEV_SECRET or len(settings.secret_key) < 32:
        problems.append("SECRET_KEY must be a random value of at least 32 characters")
    if "*" in settings.cors_origins:
        problems.append("CORS_ORIGINS must list explicit origins, not '*'")
    if "angon:angon@" in settings.database_url:
        problems.append("DATABASE_URL still uses the development credentials")
    if settings.storage_provider == "local":
        problems.append(
            "STORAGE_PROVIDER=local is development-only (media would not be served); "
            "use an object-storage backend"
        )
    if not settings.rate_limit_enabled:
        problems.append("RATE_LIMIT_ENABLED must not be false")
    return problems
