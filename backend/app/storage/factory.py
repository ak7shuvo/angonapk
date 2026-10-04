from app.core.config import Settings
from app.storage.base import StorageBackend
from app.storage.local import LocalStorage


def build_storage(settings: Settings) -> StorageBackend:
    if settings.storage_provider == "local":
        return LocalStorage(settings.storage_local_dir)
    raise ValueError(f"Unknown STORAGE_PROVIDER: {settings.storage_provider!r}")
