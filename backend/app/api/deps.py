"""FastAPI dependencies: authentication and authorization guards.

Supports both:
1. Legacy username/password tokens (deprecated when Keycloak is active).
2. Keycloak-issued access tokens (OIDC / JWT).

The active authentication mode is determined by the presence of Keycloak
configuration. When KEYCLOOK_ISSUER and KEYCLOOK_CLIENT_ID are set, the
system validates Keycloak tokens. Otherwise, it falls back to legacy JWT tokens.
"""
from __future__ import annotations

from typing import Optional

import jwt
from datetime import datetime
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pymongo.database import Database

from app.config import settings
from app.core.errors import ForbiddenError, UnauthorizedError
from app.core.rbac import Permission, Role, role_has_permission, is_operator
from app.core.security import (
    decode_access_token_legacy,
    decode_access_token_keycloak,
)
from app.db.mongo import get_db
from app.services import user_service

_bearer = HTTPBearer(auto_error=False)


class CurrentUser:
    def __init__(self, doc: dict, keycloak_payload: dict = None):
        self.id: str = str(doc["_id"])
        self.username: str = doc["username"]
        self.email: str = doc["email"]
        self.full_name: str = doc.get("full_name", "")
        # Authorization is sourced from the persisted user record in both
        # auth modes; a token claim must not override current role assignment.
        role_str = doc.get("role", "USER")
        self.role = self._resolve_legacy_role(role_str)
        self.is_active: bool = doc.get("is_active", True)
        self.token_version: int = doc.get("token_version", 1)
        # Geographic scope from user document
        self.region: Optional[str] = doc.get("region")
        self.township: Optional[str] = doc.get("township")
        self.region_id: Optional[str] = doc.get("region_id")
        self.sub_region_id: Optional[str] = doc.get("sub_region_id")
        self.keycloak_user_id: str = doc.get("keycloak_user_id", "")
        self.keycloak_payload: dict = keycloak_payload or {}
        # Timestamps are part of the client-facing user contract; the Flutter
        # UserModel requires `created_at`, so they must reach /auth/me too.
        self.created_at: Optional[datetime] = doc.get("created_at")
        self.updated_at: Optional[datetime] = doc.get("updated_at")
        self.last_login_at: Optional[datetime] = doc.get("last_login_at")

    def _resolve_legacy_role(self, role_str: str) -> Role:
        """Resolve legacy role strings to the new hierarchical Role enum.

        Maps:
        - "ADMIN" -> Role.OVERALL_ADMIN (backward compatibility)
        - "USER" -> Role.OPERATOR (backward compatibility)
        - Any other value -> Role.OPERATOR (default)
        """
        role_upper = role_str.upper()
        if role_upper == "ADMIN":
            return Role.OVERALL_ADMIN
        elif role_upper == "USER":
            return Role.OPERATOR
        else:
            # Try to match by enum value
            try:
                return Role(role_upper)
            except ValueError:
                return Role.OPERATOR  # Default fallback

    def _resolve_role_from_keycloak(self, payload: dict) -> Role:
        """Resolve the application role from Keycloak claims.

        Keycloak may map roles via:
        - realm_access.roles
        - resource_access[client_id].roles
        - Custom claims (top-level 'role' field for legacy tokens)
        """
        # Check realm_access.roles first
        realm_roles = payload.get("realm_access", {}).get("roles", [])
        if realm_roles:
            # Map Keycloak role names to application roles
            for role_name in realm_roles:
                role_name_lower = role_name.lower()
                if role_name_lower in ("overall_admin", "admin", "superadmin"):
                    return Role.OVERALL_ADMIN
                elif role_name_lower in ("regional_admin", "regionaladmin"):
                    return Role.REGIONAL_ADMIN
                elif role_name_lower in ("supervisor", "supervisors"):
                    return Role.SUPERVISOR
                elif role_name_lower in ("operator", "operators"):
                    return Role.OPERATOR

        # Check resource_access for client-specific roles
        resource_access = payload.get("resource_access", {})
        for client_id, client_data in resource_access.items():
            client_roles = client_data.get("roles", [])
            for role_name in client_roles:
                role_name_lower = role_name.lower()
                if role_name_lower in ("overall_admin", "admin", "superadmin"):
                    return Role.OVERALL_ADMIN
                elif role_name_lower in ("regional_admin", "regionaladmin"):
                    return Role.REGIONAL_ADMIN
                elif role_name_lower in ("supervisor", "supervisors"):
                    return Role.SUPERVISOR
                elif role_name_lower in ("operator", "operators"):
                    return Role.OPERATOR

        # Fallback: check for top-level 'role' claim (legacy JWT tokens)
        # This handles legacy tokens that have 'role' as a top-level claim
        top_level_role = payload.get("role")
        if top_level_role:
            role_upper = top_level_role.upper()
            if role_upper == "ADMIN":
                return Role.OVERALL_ADMIN
            elif role_upper == "USER":
                return Role.OPERATOR
            else:
                try:
                    return Role(role_upper)
                except ValueError:
                    return Role.OPERATOR

        # Ultimate fallback
        return Role.USER


def _get_keycloak_payload(credentials: str) -> dict[str, Any]:
    """Validate and decode a Keycloak-issued access token.

    Returns the decoded payload dict, or raises UnauthorizedError.
    """
    try:
        payload = decode_access_token_keycloak(credentials)
        return payload
    except jwt.ExpiredSignatureError:
        raise UnauthorizedError("Your session has expired. Please log in again.")
    except jwt.PyJWTError as exc:
        raise UnauthorizedError(f"Invalid authentication token: {exc}")


def get_current_user(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Database = Depends(get_db),
) -> CurrentUser:
    """Authenticate the current user from the JWT access token.

    Supports two modes:
    1. Keycloak mode: Validates Keycloak-issued tokens with iss/aud checks.
    2. Legacy mode: Validates locally-issued JWT tokens (deprecated).

    Returns a CurrentUser object populated with user data from MongoDB and
    role/scope information from the token.
    """
    if credentials is None or not credentials.credentials:
        raise UnauthorizedError("Authentication required.")

    token = credentials.credentials

    # Determine authentication mode based on Keycloak configuration
    has_keycloak_config = bool(
        getattr(settings, "KEYCLOOK_ISSUER", None)
        and getattr(settings, "KEYCLOOK_CLIENT_ID", None)
    )

    keycloak_payload: dict[str, Any] = {}

    if has_keycloak_config:
        # Keycloak mode: validate Keycloak token
        try:
            keycloak_payload = _get_keycloak_payload(token)
        except UnauthorizedError:
            raise
        except Exception:
            raise UnauthorizedError("Invalid authentication token.")
        user_id = keycloak_payload.get("sub")
    else:
        # Legacy mode: validate locally-issued JWT token (decoded once).
        try:
            legacy_payload = decode_access_token_legacy(token)
        except jwt.ExpiredSignatureError:
            raise UnauthorizedError("Your session has expired. Please log in again.")
        except jwt.PyJWTError:
            raise UnauthorizedError("Invalid authentication token.")
        user_id = legacy_payload.get("sub")

    if not user_id:
        raise UnauthorizedError("Invalid authentication token: no user identifier.")

    doc = user_service.get_by_id(db, user_id)
    if not doc:
        raise UnauthorizedError("User no longer exists.")
    if not doc.get("is_active", True):
        raise ForbiddenError("Your account has been disabled.")

    if has_keycloak_config:
        return CurrentUser(doc, keycloak_payload=keycloak_payload)

    # Legacy mode: a role, status or area change bumps token_version, which
    # invalidates every access token issued before it.
    if legacy_payload.get("token_version") != doc.get("token_version", 1):
        raise UnauthorizedError("Your session is no longer valid. Please log in again.")
    # Role and area come from the database, never from token claims.
    return CurrentUser(doc)


def require_permission(permission: Permission):
    """Dependency factory enforcing a permission server-side.

    Enforces both permission and geographic scope based on the user's role.
    """

    def _guard(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        # First check role-based permission
        if not role_has_permission(user.role, permission):
            raise ForbiddenError()

        # Additional scope-based filtering happens in the service layer.
        # This guard ensures the role has the minimum required permission.
        return user

    return _guard


def require_regional_scope(permission: Permission):
    """Dependency that also enforces geographic scope.

    This is a meta-dependency that can be used alongside require_permission
    to ensure scope-aware operations. The actual scope check is performed
    in the service layer based on the user's region/township fields.
    """

    def _guard(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        # Check role-based permission first
        if not role_has_permission(user.role, permission):
            raise ForbiddenError()

        # Additional scope validation can be added here based on:
        # - user.region
        # - user.township
        # - The specific resource being accessed
        return user

    return _guard


def require_admin(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    if user.role != Role.OVERALL_ADMIN and user.role != Role.ADMIN:
        raise ForbiddenError()
    return user


def require_role(
    allowed_roles: list[Role],
):
    """Dependency factory that checks if the user has one of the allowed roles."""

    def _guard(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if user.role not in allowed_roles:
            raise ForbiddenError()
        return user

    return _guard
