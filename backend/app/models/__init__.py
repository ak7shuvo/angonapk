"""Import every model here so Base.metadata (and Alembic) sees all tables."""

from app.models.profile import Profile
from app.models.revoked_token import RevokedToken
from app.models.user import User

__all__ = ["Profile", "RevokedToken", "User"]
