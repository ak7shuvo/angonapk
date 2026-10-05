"""Pure-ASGI middleware: request size limits and security headers."""

import json

from fastapi import HTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class BodySizeLimitMiddleware:
    """Rejects oversized request bodies early with 413.

    Checked twice: by the declared Content-Length (before reading anything) and
    by counting bytes as they stream in, so a client that lies about, or omits,
    the length still cannot make the server buffer an unbounded body.
    Uploads get their own larger limit.
    """

    def __init__(
        self,
        app: ASGIApp,
        *,
        default_limit: int,
        upload_limit: int,
        upload_prefix: str = "/api/v1/media",
    ) -> None:
        self.app = app
        self.default_limit = default_limit
        self.upload_limit = upload_limit
        self.upload_prefix = upload_prefix

    def _limit_for(self, scope: Scope) -> int:
        if scope["method"] == "POST" and scope["path"].rstrip("/") == self.upload_prefix:
            return self.upload_limit
        return self.default_limit

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] in ("GET", "HEAD", "OPTIONS"):
            await self.app(scope, receive, send)
            return
        limit = self._limit_for(scope)
        headers = dict(scope["headers"])
        declared = headers.get(b"content-length")
        if declared and declared.isdigit() and int(declared) > limit:
            await self._reject(send)
            return

        seen = 0

        async def counting_receive() -> Message:
            nonlocal seen
            message = await receive()
            if message["type"] == "http.request":
                seen += len(message.get("body", b""))
                if seen > limit:
                    # FastAPI's own class so body parsing re-raises it as a 413
                    # instead of masking it as a generic 400 parse error.
                    raise HTTPException(413, "Request body is too large")
            return message

        await self.app(scope, counting_receive, send)

    @staticmethod
    async def _reject(send: Send) -> None:
        body = json.dumps({"detail": "Request body is too large"}).encode()
        await send(
            {
                "type": "http.response.start",
                "status": 413,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode()),
                    (b"connection", b"close"),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})


class SecurityHeadersMiddleware:
    """Conservative response headers for an API (no HTML is served)."""

    def __init__(self, app: ASGIApp, *, hsts: bool) -> None:
        self.app = app
        self.extra = [
            (b"x-content-type-options", b"nosniff"),
            (b"x-frame-options", b"DENY"),
            (b"referrer-policy", b"no-referrer"),
            (b"cross-origin-resource-policy", b"same-site"),
        ]
        if hsts:
            self.extra.append(
                (b"strict-transport-security", b"max-age=31536000; includeSubDomains")
            )

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                present = {k.lower() for k, _ in message["headers"]}
                message["headers"] = [
                    *message["headers"],
                    *[(k, v) for k, v in self.extra if k not in present],
                ]
            await send(message)

        await self.app(scope, receive, with_headers)
