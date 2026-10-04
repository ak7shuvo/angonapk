from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import Tag


class TagRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_or_create(self, names: list[str]) -> list[Tag]:
        if not names:
            return []
        existing = {t.name: t for t in self.db.scalars(select(Tag).where(Tag.name.in_(names)))}
        for name in names:
            if name in existing:
                continue
            tag = Tag(name=name)
            try:
                with self.db.begin_nested():
                    self.db.add(tag)
                    self.db.flush()
            except IntegrityError:  # created concurrently by someone else
                tag = self.db.scalar(select(Tag).where(Tag.name == name))
            existing[name] = tag
        return [existing[n] for n in names]
