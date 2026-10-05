"""Small in-process sliding-window rate limiter.

Good enough to blunt password guessing, signup floods and upload/comment spam on
a single API instance. State lives in process memory: it resets on restart and is
NOT shared between workers or instances, so a multi-instance production
deployment must enforce limits at the edge (reverse proxy / API gateway) or swap
this for a shared store such as Redis. See docs/ARCHITECTURE.md.
"""

import threading
import time
from collections import defaultdict, deque
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status

from app.core.config import Settings, get_settings
from app.models import User


class RateLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()

    def check(self, key: str, limit: int, window: float, *, now: float | None = None) -> float:
        """Record one hit for `key`. Returns 0 when allowed, else seconds until a slot frees."""
        now = time.monotonic() if now is None else now
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] <= now - window:
                hits.popleft()
            if len(hits) >= limit:
                return max(0.1, hits[0] + window - now)
            hits.append(now)
            if len(self._hits) > 50_000:  # bound memory under a key-flood
                self._evict(now - window)
            return 0.0

    def _evict(self, cutoff: float) -> None:
        for key in [k for k, v in self._hits.items() if not v or v[-1] <= cutoff]:
            del self._hits[key]


limiter = RateLimiter()


def client_ip(request: Request) -> str:
    # Behind a reverse proxy run uvicorn with --proxy-headers and
    # --forwarded-allow-ips so this is the real client, not the proxy.
    return request.client.host if request.client else "unknown"


def enforce(settings: Settings, key: str, limit: int, window: float) -> None:
    if not settings.rate_limit_enabled:
        return
    wait = limiter.check(key, limit, window)
    if wait:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many requests. Please wait a moment and try again.",
            headers={"Retry-After": str(int(wait) + 1)},
        )


def limit_by_ip(scope: str, limit: int, window: float):
    """Dependency: at most `limit` calls per `window` seconds per client IP."""

    def dependency(request: Request, settings: Annotated[Settings, Depends(get_settings)]) -> None:
        enforce(settings, f"{scope}:ip:{client_ip(request)}", limit, window)

    return Depends(dependency)


def limit_by_user(scope: str, limit: int, window: float):
    """Dependency: at most `limit` calls per `window` seconds per signed-in user."""
    from app.api.deps import get_current_user  # deferred: deps imports services

    def dependency(
        user: Annotated[User, Depends(get_current_user)],
        settings: Annotated[Settings, Depends(get_settings)],
    ) -> None:
        enforce(settings, f"{scope}:user:{user.id}", limit, window)

    return Depends(dependency)
