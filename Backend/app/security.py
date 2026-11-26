from __future__ import annotations

from collections import defaultdict, deque
import hashlib
import logging
import re
import threading
import time
import uuid

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response

from app.config import Settings


_SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{8,128}$")
_RATE_LIMIT_EXEMPT_PATHS = {"/", "/health", "/docs", "/openapi.json", "/redoc"}
logger = logging.getLogger("mockexa.http")


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Add correlation and defensive response headers to every API response."""

    def __init__(self, app, *, production: bool = False):
        super().__init__(app)
        self.production = production

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        supplied = request.headers.get("x-request-id", "")
        request_id = supplied if _SAFE_REQUEST_ID.fullmatch(supplied) else str(uuid.uuid4())
        request.state.request_id = request_id
        started = time.monotonic()
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        if self.production:
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        logger.info(
            "request_complete request_id=%s method=%s path=%s status=%s latency_ms=%.1f",
            request_id,
            request.method,
            request.url.path,
            response.status_code,
            (time.monotonic() - started) * 1000,
        )
        return response


class RequestBodyLimitMiddleware(BaseHTTPMiddleware):
    """Reject declared oversized requests before JSON or file parsing begins."""

    def __init__(self, app, *, max_bytes: int):
        super().__init__(app)
        self.max_bytes = max(1, max_bytes)

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        value = request.headers.get("content-length")
        if value:
            try:
                if int(value) > self.max_bytes:
                    return JSONResponse(
                        status_code=413,
                        content={"detail": "Request body is too large."},
                    )
            except ValueError:
                return JSONResponse(
                    status_code=400,
                    content={"detail": "Invalid Content-Length header."},
                )
        return await call_next(request)


class InProcessRateLimitMiddleware(BaseHTTPMiddleware):
    """Bound abuse for one API process; production replicas should share Redis."""

    def __init__(self, app, *, requests: int, window_seconds: int):
        super().__init__(app)
        self.requests = max(1, requests)
        self.window_seconds = max(1, window_seconds)
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    @staticmethod
    def _client_key(request: Request) -> str:
        authorization = request.headers.get("authorization")
        if authorization:
            # Never retain a bearer token in process memory merely for limiting.
            return "auth:" + hashlib.sha256(authorization.encode("utf-8")).hexdigest()
        host = request.client.host if request.client else "unknown"
        return f"ip:{host}"

    def _allow(self, key: str, now: float) -> tuple[bool, int]:
        cutoff = now - self.window_seconds
        with self._lock:
            events = self._events[key]
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= self.requests:
                retry_after = max(1, int(self.window_seconds - (now - events[0])) + 1)
                return False, retry_after
            events.append(now)
            return True, 0

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if request.method == "OPTIONS" or request.url.path in _RATE_LIMIT_EXEMPT_PATHS:
            return await call_next(request)
        allowed, retry_after = self._allow(self._client_key(request), time.monotonic())
        if not allowed:
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests. Please retry shortly."},
                headers={"Retry-After": str(retry_after)},
            )
        return await call_next(request)


def install_security_middleware(app, settings: Settings) -> None:
    app.add_middleware(
        SecurityHeadersMiddleware,
        production=settings.environment.casefold() == "production",
    )
    app.add_middleware(RequestBodyLimitMiddleware, max_bytes=settings.max_request_body_bytes)
    if settings.enable_rate_limiting:
        app.add_middleware(
            InProcessRateLimitMiddleware,
            requests=settings.rate_limit_requests,
            window_seconds=settings.rate_limit_window_seconds,
        )
