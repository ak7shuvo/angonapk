from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class StoredObject:
    key: str
    url: str
    content_type: str
    size: int


class StorageBackend(Protocol):
    """Provider-agnostic object storage for images and video.

    Application code depends on this protocol only; S3, GCS, Cloudflare R2 or
    local disk are interchangeable implementations selected by configuration.
    """

    def save(self, key: str, data: bytes, content_type: str) -> StoredObject: ...

    def delete(self, key: str) -> None: ...

    def url_for(self, key: str) -> str: ...
