"""Role-Based Access Control definitions.

The server determines permissions from the user's role + geographic scope.
Clients never choose their own permissions.

Hierarchical roles:
  - Overall Administrator: global scope
  - Regional Administrator: restricted to assigned region
  - Supervisor: restricted to assigned region + township
  - Operator: restricted to assigned CCTV / ownership
"""
from __future__ import annotations

from enum import Enum


class Role(str, Enum):
    OVERALL_ADMIN = "OVERALL_ADMIN"
    REGIONAL_ADMIN = "REGIONAL_ADMIN"
    SUPERVISOR = "SUPERVISOR"
    OPERATOR = "OPERATOR"
    # Backward compatibility aliases (deprecated; use new hierarchical roles)
    USER = "USER"
    ADMIN = "ADMIN"

    # Property aliases for the new hierarchical model
    @property
    def is_overall_admin(self) -> bool:
        return self == Role.OVERALL_ADMIN or self == Role.ADMIN

    @property
    def is_regional_admin(self) -> bool:
        return self == Role.REGIONAL_ADMIN

    @property
    def is_supervisor(self) -> bool:
        return self == Role.SUPERVISOR

    @property
    def is_operator(self) -> bool:
        return self == Role.OPERATOR or self == Role.USER


class Permission(str, Enum):
    CCTV_READ = "cctv.read"
    CCTV_CREATE = "cctv.create"
    CCTV_UPDATE = "cctv.update"
    CCTV_DELETE = "cctv.delete"

    CCTV_IMAGE_UPLOAD = "cctv.image.upload"
    CCTV_IMAGE_DELETE = "cctv.image.delete"

    USER_READ = "user.read"
    USER_CREATE = "user.create"
    USER_UPDATE = "user.update"
    USER_DELETE = "user.delete"

    AUDIT_READ = "audit.read"


# Hierarchical role permissions at the role level (before scope filtering)
_ROLE_PERMISSIONS: dict[Role, set[Permission]] = {
    Role.OVERALL_ADMIN: {
        Permission.CCTV_READ,
        Permission.CCTV_CREATE,
        Permission.CCTV_UPDATE,
        Permission.CCTV_DELETE,
        Permission.CCTV_IMAGE_UPLOAD,
        Permission.CCTV_IMAGE_DELETE,
        Permission.USER_READ,
        Permission.USER_CREATE,
        Permission.USER_UPDATE,
        Permission.USER_DELETE,
        Permission.AUDIT_READ,
    },
    Role.REGIONAL_ADMIN: {
        Permission.CCTV_READ,
        Permission.CCTV_CREATE,
        Permission.CCTV_UPDATE,
        Permission.CCTV_DELETE,
        Permission.CCTV_IMAGE_UPLOAD,
        Permission.CCTV_IMAGE_DELETE,
        Permission.USER_READ,
        Permission.USER_CREATE,
        Permission.USER_UPDATE,
        Permission.USER_DELETE,
        Permission.AUDIT_READ,
    },
    Role.SUPERVISOR: {
        Permission.CCTV_READ,
        Permission.CCTV_CREATE,
        Permission.CCTV_UPDATE,
        Permission.CCTV_DELETE,
        Permission.CCTV_IMAGE_UPLOAD,
        Permission.CCTV_IMAGE_DELETE,
        Permission.USER_READ,
        Permission.USER_CREATE,
        Permission.USER_UPDATE,
        Permission.USER_DELETE,
        Permission.AUDIT_READ,
    },
    Role.OPERATOR: {
        Permission.CCTV_READ,
        Permission.CCTV_CREATE,
        Permission.CCTV_UPDATE,
        Permission.CCTV_DELETE,
        Permission.CCTV_IMAGE_UPLOAD,
        Permission.CCTV_IMAGE_DELETE,
        Permission.AUDIT_READ,
    },
}


def permissions_for_role(role: Role) -> set[Permission]:
    # Handle backward compatibility roles
    if role == Role.USER:
        return permissions_for_role(Role.OPERATOR)
    if role == Role.ADMIN:
        return permissions_for_role(Role.OVERALL_ADMIN)
    return set(_ROLE_PERMISSIONS.get(role, set()))


def role_has_permission(role: Role, permission: Permission) -> bool:
    # Handle backward compatibility roles
    if role == Role.USER:
        role = Role.OPERATOR
    if role == Role.ADMIN:
        role = Role.OVERALL_ADMIN
    return permission in _ROLE_PERMISSIONS.get(role, set())


def is_scope_broadening_admin(role: Role) -> bool:
    """Check if a role has broad administrative scope (Overall Admin only)."""
    return role == Role.OVERALL_ADMIN


def is_regional_admin(role: Role) -> bool:
    """Check if role is a Regional Administrator."""
    return role == Role.REGIONAL_ADMIN


def is_supervisor(role: Role) -> bool:
    """Check if role is a Supervisor."""
    return role == Role.SUPERVISOR


def is_operator(role: Role) -> bool:
    """Check if role is an Operator."""
    return role == Role.OPERATOR


def is_overall_admin(role: Role) -> bool:
    """Check if role is an Overall Administrator.

    Alias for is_scope_broadening_admin for backward compatibility.
    """
    return is_scope_broadening_admin(role)
