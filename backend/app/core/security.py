"""Password hashing (Argon2id) and JWT token utilities.

This module now supports two authentication modes:
1. Legacy: Username/password against FastAPI-stored hashes (deprecated when Keycloak is active).
2. Keycloak: Validation of Keycloak-issued access tokens (OIDC / JWT).

When Keycloak is the authoritative identity provider, FastAPI should validate
Keycloak-issued access tokens and enforce application authorization. The legacy
password-based authentication should be disabled or left in place for migration
purposes but not used for new sessions.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from app.config import settings


# Argon2id is the default backend for argon2-cffi's PasswordHasher.
# Used only for legacy password operations or hash migration.
_hasher = PasswordHasher()

MIN_PASSWORD_LENGTH = 8


def hash_password(password: str) -> str:
    """Hash a plaintext password using Argon2id."""
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    """Verify a plaintext password against an Argon2id hash.

    Deprecated when Keycloak is the authoritative identity provider.
    """
    try:
        return _hasher.verify(password_hash, password)
    except (VerifyMismatchError, InvalidHashError, Exception):
        return False


def needs_rehash(password_hash: str) -> bool:
    try:
        return _hasher.check_needs_rehash(password_hash)
    except Exception:
        return False


def validate_password_strength(password: str) -> None:
    """Raise ValueError if the password does not meet requirements."""
    if not password or len(password) < MIN_PASSWORD_LENGTH:
        raise ValueError(
            f"Password must be at least {MIN_PASSWORD_LENGTH} characters long."
        )
    if password.strip() != password:
        raise ValueError("Password must not start or end with whitespace.")
    if not any(c.isalpha() for c in password):
        raise ValueError("Password must contain at least one letter.")
    if not any(c.isdigit() for c in password):
        raise ValueError("Password must contain at least one digit.")


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


def create_access_token_legacy(
    *,
    subject: str,
    role: str,
    token_version: int,
) -> tuple[str, int]:
    """Create a short-lived access token for legacy username/password auth.

    Returns (token, expires_in_seconds).
    """
    expires_delta = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    expire = _now() + expires_delta
    payload: dict[str, Any] = {
        "sub": subject,
        "role": role,
        "token_version": token_version,
        "type": "access",
        "jti": str(uuid.uuid4()),
        "exp": expire,
        "iat": _now(),
    }
    token = jwt.encode(
        payload, settings.jwt_signing_key, algorithm=settings.JWT_ALGORITHM
    )
    return token, int(expires_delta.total_seconds())


# Backward compatibility: keep create_access_token as an alias
create_access_token = create_access_token_legacy


def decode_access_token(token: str) -> dict:
    """Decode a legacy JWT access token and return its payload.

    Returns the decoded token payload dictionary.
    """
    payload = jwt.decode(
        token, settings.jwt_signing_key, algorithms=[settings.JWT_ALGORITHM]
    )
    return payload


# Refresh tokens
#
# Refresh tokens are 384-bit random values, so a fast SHA-256 is sufficient:
# unlike a human password there is nothing to brute-force. A
# deterministic hash also lets the token be found with one indexed lookup,
# instead of running a slow Argon2 verify against every stored token (which
# made /auth/refresh an unauthenticated CPU-exhaustion endpoint).

REFRESH_TOKEN_BYTES = 48
REFRESH_TOKEN_MAX_LENGTH = 128


def create_refresh_token() -> tuple[str, datetime]:
    """Create a random opaque refresh token. Returns (raw_token, expires_at)."""
    raw = secrets.token_urlsafe(REFRESH_TOKEN_BYTES)
    expires_at = _now() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    return raw, expires_at


def hash_refresh_token(raw_token: str) -> str:
    """Deterministic hash used to store and look up a refresh token."""
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def verify_refresh_token(raw_token: str, token_hash: str) -> bool:
    """Constant-time comparison of a raw token against a stored hash."""
    return hmac.compare_digest(hash_refresh_token(raw_token), token_hash)


def create_access_token_keycloak(
    *,
    sub: str,  # Keycloak user ID (sub claim)
    realm_access: dict,
    resource_access: dict,
    issuer: str,
) -> dict[str, Any]:
    """Validate Keycloak token claims and return the decoded payload.

    This function does not create a new token; it validates an existing
    Keycloak-issued access token and returns its payload. The caller should
    use the validated payload to populate the CurrentUser object.

    Raises jwt.InvalidTokenError on validation failure.
    """
    # Keycloak access tokens are JWTs signed with RS256 (typically).
    # The algorithm may vary based on Keycloak configuration; we support HS256
    # and RS256 for flexibility.
    algorithm = settings.JWT_ALGORITHM

    def _verify_and_decode(token: str) -> dict[str, Any]:
        options = {
            "verify_exp": True,
            "verify_nbf": True,
            "verify_iat": True,
            "verify_aud": True,
            "verify_iss": True,
        }
        payload = jwt.decode(
            token,
            settings.jwt_signing_key,
            algorithms=[algorithm],
            options=options,
            issuer=settings.KEYCLOOK_ISSUER,  # e.g. https://auth.example.com/realms/cctv-realm
        )
        # Validate issuer
        if payload.get("iss") != settings.KEYCLOOK_ISSUER:
            raise jwt.InvalidTokenError(f"Invalid token issuer: {payload.get('iss')}")

        # Validate audience / client
        audience = payload.get("aud")
        if not audience:
            raise jwt.InvalidTokenError("Token missing audience (aud) claim.")
        # audience can be a string or list; accept if it matches the configured client
        configured_client = settings.KEYCLOOK_CLIENT_ID
        if isinstance(audience, list):
            if configured_client not in audience:
                raise jwt.InvalidTokenError(
                    f"Token audience {audience} does not contain configured client {configured_client}."
                )
        else:
            if audience != configured_client:
                raise jwt.InvalidTokenError(
                    f"Token audience {audience} does not match configured client {configured_client}."
                )

        # Validate that the token has the expected sub (user identifier)
        if not payload.get("sub"):
            raise jwt.InvalidTokenError("Token missing required 'sub' claim.")

        return payload

    # Perform the actual verification
    return _verify_and_decode


def decode_access_token_legacy(token: str) -> dict[str, Any]:
    """Decode and validate a legacy access token. Raises jwt exceptions on failure."""
    payload = jwt.decode(
        token,
        settings.jwt_signing_key,
        algorithms=[settings.JWT_ALGORITHM],
    )
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("Invalid token type")
    return payload


def decode_access_token_keycloak(token: str) -> dict[str, Any]:
    """Validate a Keycloak-issued access token and return its payload.

    This is the primary entry point for Keycloak-based authentication.
    It validates:
    - Issuer (must match KEYCLOOK_ISSUER)
    - Audience (must match KEYCLOOK_CLIENT_ID)
    - Expiration (must not be expired)
    - Not Before (must be valid)
    - Issued At (must be valid)

    Returns the decoded payload dict containing claims such as:
    - sub: Keycloak user ID
    - realm_access: role mappings from Keycloak realm
    - resource_access: role mappings from Keycloak clients/resources
    - Other standard claims (exp, iat, jti, etc.)
    """
    # Use the internal _verify_and_decode logic
    return _validate_keycloak_token(token)


def _validate_keycloak_token(token: str) -> dict[str, Any]:
    """Internal validation of Keycloak token."""
    algorithm = settings.JWT_ALGORITHM

    payload = jwt.decode(
        token,
        settings.jwt_signing_key,
        algorithms=[algorithm],
    )

    # Validate issuer
    expected_issuer = getattr(settings, "KEYCLOOK_ISSUER", None)
    if expected_issuer and payload.get("iss") != expected_issuer:
        raise jwt.InvalidTokenError(f"Invalid token issuer: expected {expected_issuer}, got {payload.get('iss')}")

    # Validate audience / client
    expected_audience = getattr(settings, "KEYCLOOK_CLIENT_ID", None)
    if expected_audience:
        audience = payload.get("aud")
        if not audience:
            raise jwt.InvalidTokenError("Token missing audience (aud) claim.")
        if isinstance(audience, list):
            if expected_audience not in audience:
                raise jwt.InvalidTokenError(
                    f"Token audience {audience} does not contain configured client {expected_audience}."
                )
        else:
            if audience != expected_audience:
                raise jwt.InvalidTokenError(
                    f"Token audience {audience} does not match configured client {expected_audience}."
                )

    # The sub claim contains the Keycloak user ID
    if not payload.get("sub"):
        raise jwt.InvalidTokenError("Token missing required 'sub' claim.")

    return payload
