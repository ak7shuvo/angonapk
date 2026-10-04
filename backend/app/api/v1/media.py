import uuid

from fastapi import APIRouter, HTTPException, Request, Response, UploadFile, status

from app.api.deps import AppSettings, CurrentUser, Media
from app.schemas.media import MediaAssetRead
from app.services.media_service import MediaError

router = APIRouter(prefix="/media", tags=["media"])


@router.post("", response_model=MediaAssetRead, status_code=status.HTTP_201_CREATED)
def upload_media(
    file: UploadFile, request: Request, user: CurrentUser, media: Media, settings: AppSettings
) -> MediaAssetRead:
    """Upload one image (multipart field `file`). JPEG/PNG/WebP, validated by decoding."""
    limit = settings.max_upload_bytes
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > limit + 64 * 1024:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "Image is too large")
    data = file.file.read(limit + 1)  # never buffer more than limit+1 bytes
    try:
        return media.upload_image(user, data)
    except MediaError as exc:
        raise HTTPException(exc.status_code, exc.message) from None


@router.delete("/{asset_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_media(asset_id: uuid.UUID, user: CurrentUser, media: Media) -> Response:
    """Remove an uploaded image that has not been attached to anything yet."""
    try:
        media.delete_unattached(user, asset_id)
    except MediaError as exc:
        code = 404 if exc.status_code == 422 else exc.status_code
        raise HTTPException(code, exc.message) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)
