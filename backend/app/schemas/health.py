from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: str  # "ok" | "degraded"
    environment: str
    database: str  # "ok" | "unavailable"
