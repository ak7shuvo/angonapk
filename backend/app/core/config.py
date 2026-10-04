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

    storage_provider: str = "local"
    storage_local_dir: str = "./var/uploads"

    # Uploads (images). Validated server-side regardless of what the client claims.
    max_upload_bytes: int = 10 * 1024 * 1024
    max_image_edge: int = 4096  # longest side after downscaling
    max_image_pixels: int = 60_000_000  # decompression-bomb guard

    @field_validator("cors_origins", mode="before")
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
    if settings.is_production and (
        settings.secret_key == _DEV_SECRET or len(settings.secret_key) < 32
    ):
        raise RuntimeError("SECRET_KEY must be set to a random value (>= 32 chars) in production")
    return settings
