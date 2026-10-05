import uuid
from datetime import UTC, datetime

from sqlalchemy import JSON, DateTime, Float, Index, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _now() -> datetime:
    return datetime.now(UTC)


class Place(Base):
    """A destination: the anchor that posts and stories can point at.

    Places are curated (created by admins or seed scripts), not user-generated.
    """

    __tablename__ = "places"
    __table_args__ = (
        Index("ix_places_division_district", "division", "district"),
        Index("ix_places_lat_lng", "latitude", "longitude"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(120), index=True)
    # Name in the local script (e.g. Bengali), shown alongside `name`.
    name_local: Mapped[str | None] = mapped_column(String(120))
    slug: Mapped[str] = mapped_column(String(140), unique=True, index=True)
    description: Mapped[str] = mapped_column(Text, default="")
    cover_url: Mapped[str | None] = mapped_column(String(2048))
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    country: Mapped[str] = mapped_column(String(80), default="Bangladesh")
    division: Mapped[str | None] = mapped_column(String(80))
    district: Mapped[str | None] = mapped_column(String(80))
    upazila: Mapped[str | None] = mapped_column(String(80))
    # Free-form extras (source, coordinate precision, seed flag, ...). Never user input.
    meta: Mapped[dict] = mapped_column("metadata", JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now
    )
