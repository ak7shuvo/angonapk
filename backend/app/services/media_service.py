import io
import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.config import Settings
from app.models import MediaAsset, User
from app.repositories.media_repository import MediaRepository
from app.storage.base import StorageBackend

log = logging.getLogger(__name__)

# Detected format -> (content type, extension). Anything else is rejected.
ALLOWED_FORMATS = {
    "JPEG": ("image/jpeg", "jpg"),
    "PNG": ("image/png", "png"),
    "WEBP": ("image/webp", "webp"),
}


class MediaError(Exception):
    """Base class; `status_code` is what the API should answer with."""

    status_code = 400

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class UnsupportedMediaError(MediaError):
    status_code = 415


class TooLargeError(MediaError):
    status_code = 413


class AssetNotUsableError(MediaError):
    status_code = 422


class AssetInUseError(MediaError):
    status_code = 409


@dataclass(frozen=True)
class ProcessedImage:
    data: bytes
    content_type: str
    extension: str
    width: int
    height: int


def process_image(data: bytes, settings: Settings) -> ProcessedImage:
    """Validate by decoding (not by trusting the filename/content-type), then
    re-encode. Re-encoding drops EXIF (including GPS) and any appended payload."""
    if len(data) > settings.max_upload_bytes:
        raise TooLargeError(f"Image is larger than {settings.max_upload_bytes // (1024 * 1024)} MB")
    if not data:
        raise UnsupportedMediaError("Empty file")
    Image.MAX_IMAGE_PIXELS = settings.max_image_pixels
    try:
        probe = Image.open(io.BytesIO(data))
        fmt = probe.format
        probe.verify()
        if fmt not in ALLOWED_FORMATS:
            raise UnsupportedMediaError("Only JPEG, PNG and WebP images are supported")
        img = Image.open(io.BytesIO(data))
        img.load()
    except MediaError:
        raise
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, SyntaxError, ValueError):
        raise UnsupportedMediaError("File is not a valid image") from None

    img = ImageOps.exif_transpose(img)
    img.thumbnail((settings.max_image_edge, settings.max_image_edge))
    content_type, ext = ALLOWED_FORMATS[fmt]
    out = io.BytesIO()
    if fmt == "JPEG":
        img.convert("RGB").save(out, "JPEG", quality=88, optimize=True)
    elif fmt == "PNG":
        img.save(out, "PNG", optimize=True)
    else:
        img.save(out, "WEBP", quality=88)
    return ProcessedImage(out.getvalue(), content_type, ext, img.width, img.height)


class MediaService:
    def __init__(self, repo: MediaRepository, storage: StorageBackend, settings: Settings) -> None:
        self.repo = repo
        self.storage = storage
        self.settings = settings

    def upload_image(self, owner: User, data: bytes) -> MediaAsset:
        image = process_image(data, self.settings)
        key = f"u/{owner.id.hex}/{uuid.uuid4().hex}.{image.extension}"
        stored = self.storage.save(key, image.data, image.content_type)
        asset = MediaAsset(
            owner_id=owner.id,
            storage_key=key,
            url=stored.url,
            content_type=image.content_type,
            size_bytes=len(image.data),
            width=image.width,
            height=image.height,
        )
        try:
            return self.repo.add(asset)
        except Exception:
            self.storage.delete(key)
            raise

    def claim(self, owner: User, ids: list[uuid.UUID]) -> list[MediaAsset]:
        """Resolve asset ids for attachment: must exist, be the owner's and be unattached.
        Order of `ids` is preserved."""
        if len(set(ids)) != len(ids):
            raise AssetNotUsableError("Duplicate media ids")
        found = self.repo.get_many(ids)
        assets = []
        for asset_id in ids:
            asset = found.get(asset_id)
            if asset is None or asset.owner_id != owner.id:
                raise AssetNotUsableError("Unknown media id")
            if self.repo.is_attached(asset_id):
                raise AssetNotUsableError("Media is already used")
            assets.append(asset)
        return assets

    def delete_unattached(self, owner: User, asset_id: uuid.UUID) -> None:
        asset = self.repo.get(asset_id)
        if asset is None or asset.owner_id != owner.id:
            raise AssetNotUsableError("Unknown media id")
        if self.repo.is_attached(asset_id):
            raise AssetInUseError("Media is attached to content")
        self.release([asset])

    def release(self, assets: list[MediaAsset]) -> None:
        """Delete assets (row + stored object) that nothing references any more."""
        for asset in assets:
            if self.repo.is_attached(asset.id):
                continue
            key = asset.storage_key
            self.repo.delete(asset)
            try:
                self.storage.delete(key)
            except Exception:  # best effort; an orphaned file is cheaper than a failed request
                log.exception("failed to delete stored object %s", key)

    def cleanup_orphans(self, older_than: timedelta = timedelta(hours=24)) -> int:
        cutoff = datetime.now(UTC) - older_than
        orphans = self.repo.unattached_before(cutoff)
        self.release(orphans)
        return len(orphans)
