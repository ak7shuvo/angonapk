import uuid

from pydantic import BaseModel, ConfigDict


class MediaAssetRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    url: str
    kind: str
    content_type: str
    size_bytes: int
    width: int | None
    height: int | None
