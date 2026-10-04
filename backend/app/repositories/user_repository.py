import uuid

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models import Profile, RevokedToken, User


class UserRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, user_id: uuid.UUID) -> User | None:
        return self.db.get(User, user_id)

    def get_by_identifier(self, identifier: str) -> User | None:
        value = identifier.strip().lower()
        stmt = select(User).where(or_(User.email == value, User.username == value))
        return self.db.execute(stmt).unique().scalar_one_or_none()

    def get_by_username(self, username: str) -> User | None:
        stmt = select(User).where(User.username == username.strip().lower())
        return self.db.execute(stmt).unique().scalar_one_or_none()

    def exists(self, *, email: str, username: str) -> tuple[bool, bool]:
        """Returns (email_taken, username_taken)."""
        rows = self.db.execute(
            select(User.email, User.username).where(
                or_(User.email == email, User.username == username)
            )
        ).all()
        return (any(r.email == email for r in rows), any(r.username == username for r in rows))

    def add(self, *, email: str, username: str, password_hash: str) -> User:
        user = User(email=email, username=username, password_hash=password_hash)
        user.profile = Profile()
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user

    def save(self, user: User) -> User:
        self.db.commit()
        self.db.refresh(user)
        return user

    def revoke_token(self, jti: str, expires_at) -> None:
        if self.db.get(RevokedToken, jti) is None:
            self.db.add(RevokedToken(jti=jti, expires_at=expires_at))
            self.db.commit()

    def is_token_revoked(self, jti: str) -> bool:
        return self.db.get(RevokedToken, jti) is not None
