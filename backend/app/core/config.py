from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings, loaded from environment variables / `.env`."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "ANGON API"
    app_env: str = "development"  # development | staging | production
    secret_key: str = "change-me"
    database_url: str = "postgresql+psycopg://angon:angon@localhost:5432/angon"
    cors_origins: list[str] = ["http://localhost:3000"]

    storage_provider: str = "local"
    storage_local_dir: str = "./var/uploads"

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
    if settings.is_production and settings.secret_key == "change-me":
        raise RuntimeError("SECRET_KEY must be set in production")
    return settings
