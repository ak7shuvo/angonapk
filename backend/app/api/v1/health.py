from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.schemas.health import HealthResponse
from app.services.health import database_is_available

router = APIRouter(tags=["system"])


@router.get("/health", response_model=HealthResponse)
def health(
    db: Annotated[Session, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> HealthResponse:
    db_ok = database_is_available(db)
    return HealthResponse(
        status="ok" if db_ok else "degraded",
        environment=settings.app_env,
        database="ok" if db_ok else "unavailable",
    )
