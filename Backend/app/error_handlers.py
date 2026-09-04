"""
Global exception handlers for consistent JSON error responses.

An iOS client (or any HTTP client) must always receive JSON — never HTML
error pages or Python tracebacks. FastAPI's built-in HTTPException handler
already returns JSON, so we only add handlers for the two cases it doesn't
cover:

1. RequestValidationError (Pydantic validation failures) — normalize into
   the same {"detail": "..."} shape the rest of the API uses.
2. Unhandled Exception — catch-all that returns 500 with a generic message,
   logging the real error server-side without exposing internals to the client.
"""
from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger("prepai.errors")


def register_error_handlers(app: FastAPI) -> None:
    """Call once during app startup to install global handlers."""

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
        # Flatten Pydantic's verbose error list into a concise string.
        messages = []
        for error in exc.errors():
            loc = " → ".join(str(part) for part in error["loc"])
            messages.append(f"{loc}: {error['msg']}")
        detail = "; ".join(messages)
        return JSONResponse(status_code=422, content={"detail": detail})

    @app.exception_handler(Exception)
    async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
        # Log the real exception for debugging; return a safe message to the client.
        logger.exception("Unhandled exception on %s %s", request.method, request.url.path)
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})
