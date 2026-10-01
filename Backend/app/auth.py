"""
Authentication dependency for FastAPI.

Validates JWT Bearer tokens compatible with Supabase Auth.
Supports both the modern asymmetric JWKS standard (RS256) used by new
Supabase projects, and a legacy HS256 fallback for local testing.

The iOS app authenticates with Supabase Auth directly, receives a JWT,
and sends it to this backend as:

    Authorization: Bearer <jwt>

This backend NEVER issues tokens — it only validates them.
"""
from __future__ import annotations

import logging
from functools import lru_cache

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings, get_settings

logger = logging.getLogger("mockexa.auth")

_bearer_scheme = HTTPBearer()

@lru_cache
def _get_jwks_client(supabase_url: str) -> jwt.PyJWKClient:
    jwks_url = f"{supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"
    return jwt.PyJWKClient(jwks_url)


def _validate_token(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    settings: Settings = Depends(get_settings),
) -> tuple[str, str]:
    if not settings.supabase_url and not settings.supabase_jwt_secret:
        logger.error("Neither SUPABASE_URL nor SUPABASE_JWT_SECRET is configured.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication is not configured on this server.",
        )

    token = credentials.credentials
    try:
        unverified_header = jwt.get_unverified_header(token)
        alg = unverified_header.get("alg")

        if alg == "HS256" and settings.supabase_jwt_secret:
            # Local fallback / legacy support
            payload = jwt.decode(
                token,
                settings.supabase_jwt_secret,
                algorithms=["HS256"],
                options={"require": ["sub"]},
            )
        elif alg in ("RS256", "ES256") and settings.supabase_url:
            # Modern JWKS support
            jwks_client = _get_jwks_client(settings.supabase_url)
            signing_key = jwks_client.get_signing_key_from_jwt(token)
            payload = jwt.decode(
                token,
                signing_key.key,
                algorithms=[alg],
                audience="authenticated",
                options={"require": ["sub"]},
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Unsupported token algorithm ({alg}) or missing configuration.",
            )

    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired.",
        )
    except jwt.PyJWKClientError as exc:
        logger.error("JWKS client error: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unable to verify token against identity provider.",
        )
    except jwt.InvalidTokenError as exc:
        logger.info("JWT validation failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Unexpected error during token validation: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
        )

    user_id: str | None = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token does not contain a valid user identity.",
        )

    return user_id, token


import re

def get_current_user_id(data: tuple[str, str] = Depends(_validate_token)) -> str:
    return data[0]


def get_raw_jwt_token(data: tuple[str, str] = Depends(_validate_token)) -> str:
    return data[1]


def get_user_display_name_from_token(token: str | None) -> str | None:
    if not token:
        return None
    try:
        payload = jwt.decode(token, options={"verify_signature": False})
        user_meta = payload.get("user_metadata")
        if isinstance(user_meta, dict):
            for key in ("full_name", "name", "display_name"):
                val = user_meta.get(key)
                if val and str(val).strip():
                    return str(val).strip()
        for key in ("full_name", "name", "display_name"):
            val = payload.get(key)
            if val and str(val).strip():
                return str(val).strip()
        email = payload.get("email")
        if email and "@" in str(email):
            prefix = str(email).split("@")[0]
            clean_name = re.sub(r"[._0-9]+", " ", prefix).strip().title()
            if clean_name:
                return clean_name
    except Exception:
        pass
    return None


