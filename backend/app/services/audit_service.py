"""Audit logging service."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from pymongo.database import Database

LOGIN_SUCCESS = "LOGIN_SUCCESS"
LOGIN_FAILED = "LOGIN_FAILED"
LOGOUT = "LOGOUT"
CCTV_CREATED = "CREATE_CCTV"
CCTV_UPDATED = "UPDATE_CCTV"
CCTV_DELETED = "DELETE_CCTV"
CCTV_VIEWED = "VIEW_CCTV"
IMAGE_UPLOADED = "CREATE_CCTV_IMAGE"
IMAGE_DELETED = "DELETE_CCTV_IMAGE"
USER_CREATED = "USER_CREATED"
USER_UPDATED = "USER_UPDATED"
USER_DISABLED = "USER_DISABLED"
USER_DELETED = "USER_DELETED"
ROLE_CHANGED = "ROLE_CHANGED"
PASSWORD_CHANGED = "PASSWORD_CHANGED"


def _role_name(role: Any) -> Optional[str]:
    if role is None:
        return None
    role_value = getattr(role, "value", str(role))
    return {
        "ADMIN": "System Admin",
        "OVERALL_ADMIN": "System Admin",
        "REGIONAL_ADMIN": "Regional Admin",
        "SUPERVISOR": "Supervisor",
        "OPERATOR": "Operator",
        "USER": "Operator",
    }.get(role_value, role_value)


def record(
    db: Database,
    *,
    action: str,
    user: Any = None,
    cctv: Optional[dict] = None,
    user_id: Optional[str] = None,
    username: Optional[str] = None,
    user_role: Any = None,
    resource_type: Optional[str] = None,
    resource_id: Optional[str] = None,
    cctv_id: Optional[str] = None,
    cctv_name: Optional[str] = None,
    region_id: Optional[str] = None,
    sub_region_id: Optional[str] = None,
    region: Optional[str] = None,
    sub_region: Optional[str] = None,
    cctv_created_by: Optional[str] = None,
    ip_address: Optional[str] = None,
    request: Any = None,
    metadata: Optional[dict[str, Any]] = None,
) -> None:
    """Persist an audit event; database failures are surfaced to the caller.

    Never include passwords, password hashes, tokens, or secrets in metadata.
    """
    if user is not None:
        user_id = user.id
        username = user.username
        user_role = user.role

    if cctv is not None:
        cctv_id = cctv.get("cctv_id", cctv_id)
        cctv_name = cctv.get("name") or cctv_id
        region_id = cctv.get("region_id", region_id)
        sub_region_id = cctv.get("sub_region_id", sub_region_id)
        region = cctv.get("region", region)
        sub_region = cctv.get("township", sub_region)
        cctv_created_by = cctv.get("created_by", cctv_created_by)

    request_details = None
    if request is not None:
        ip_address = request.client.host if request.client else ip_address
        request_details = {
            "method": request.method,
            "path": request.url.path,
            "user_agent": request.headers.get("user-agent"),
        }

    db.audit_logs.insert_one(
        {
            "user_id": user_id,
            "username": username,
            "user_role": _role_name(user_role),
            "action": action,
            "resource_type": resource_type,
            "resource_id": resource_id,
            "cctv_id": cctv_id,
            "cctv_name": cctv_name,
            "region_id": region_id,
            "sub_region_id": sub_region_id,
            "region": region,
            "sub_region": sub_region,
            "cctv_created_by": cctv_created_by,
            "timestamp": datetime.now(tz=timezone.utc),
            "ip_address": ip_address,
            "request_details": request_details,
            "metadata": metadata or {},
        }
    )
