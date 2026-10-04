import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.schemas.profile import ProfileRead


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    username: str
    role: str
    created_at: datetime
    profile: ProfileRead
