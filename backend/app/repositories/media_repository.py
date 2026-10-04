import uuid
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ASSET_REFERENCES, MediaAsset


class MediaRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def add(self, asset: MediaAsset) -> MediaAsset:
        self.db.add(asset)
        self.db.commit()
        self.db.refresh(asset)
        return asset

    def get(self, asset_id: uuid.UUID) -> MediaAsset | None:
        return self.db.get(MediaAsset, asset_id)

    def get_many(self, ids: list[uuid.UUID]) -> dict[uuid.UUID, MediaAsset]:
        if not ids:
            return {}
        rows = self.db.scalars(select(MediaAsset).where(MediaAsset.id.in_(ids)))
        return {a.id: a for a in rows}

    def is_attached(self, asset_id: uuid.UUID) -> bool:
        return any(
            self.db.scalar(select(ref).where(ref == asset_id).limit(1)) is not None
            for ref in ASSET_REFERENCES
        )

    def delete(self, asset: MediaAsset) -> None:
        self.db.delete(asset)
        self.db.commit()

    def unattached_before(self, cutoff: datetime) -> list[MediaAsset]:
        rows = self.db.scalars(select(MediaAsset).where(MediaAsset.created_at < cutoff))
        return [a for a in rows if not self.is_attached(a.id)]
