"""Scope-filtered audit log API routes."""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query, status
from pymongo.database import Database

from app.api.deps import CurrentUser, require_permission
from app.config import settings
from app.core.rbac import Permission
from app.core.errors import success
from app.db.mongo import get_db

router = APIRouter(prefix="/audit-logs", tags=["Audit Logs"])


def _serialize(doc: dict) -> dict:
    return {
        "id": str(doc["_id"]),
        "user_id": doc.get("user_id"),
        "username": doc.get("username"),
        "user_role": doc.get("user_role"),
        "action": doc.get("action"),
        "resource_type": doc.get("resource_type"),
        "resource_id": doc.get("resource_id"),
        "cctv_id": doc.get("cctv_id"),
        "cctv_name": doc.get("cctv_name"),
        "region_id": doc.get("region_id"),
        "sub_region_id": doc.get("sub_region_id"),
        "timestamp": doc.get("timestamp"),
        "ip_address": doc.get("ip_address"),
        "request_details": doc.get("request_details"),
        "metadata": doc.get("metadata", {}),
    }


@router.get("", status_code=status.HTTP_200_OK)
def list_audit_logs(
    page: int = Query(1, ge=1),
    limit: int = Query(settings.DEFAULT_PAGE_SIZE, ge=1, le=settings.MAX_PAGE_SIZE),
    action: Optional[str] = Query(None, max_length=64),
    user_id: Optional[str] = Query(None, max_length=64),
    resource_id: Optional[str] = Query(None, max_length=64),
    user: CurrentUser = Depends(require_permission(Permission.AUDIT_READ)),
    db: Database = Depends(get_db),
):
    filters: dict = {}
    if action:
        filters["action"] = action
    if user_id:
        filters["user_id"] = user_id
    if resource_id:
        filters["resource_id"] = resource_id

    if user.role.is_overall_admin:
        query = filters
    elif user.role.is_operator:
        scope = {"cctv_created_by": user.id}
        query = {"$and": [filters, scope]} if filters else scope
    else:
        region_field = "region_id" if user.region_id else "region"
        scope: dict = {region_field: user.region_id or user.region}
        if region_field == "region":
            scope["region_id"] = None
        if user.role.is_supervisor:
            sub_region_field = "sub_region_id" if user.sub_region_id else "sub_region"
            scope[sub_region_field] = user.sub_region_id or user.township
            if sub_region_field == "sub_region":
                scope["sub_region_id"] = None
        if not all(scope.values()):
            from app.core.errors import ForbiddenError

            raise ForbiddenError("Your account has no complete audit scope assigned.")
        query = {"$and": [filters, scope]} if filters else scope

    skip = (page - 1) * limit
    total = db.audit_logs.count_documents(query)
    cursor = (
        db.audit_logs.find(query).sort("timestamp", -1).skip(skip).limit(limit)
    )
    items = [_serialize(d) for d in cursor]
    pages = (total + limit - 1) // limit if limit else 0
    return success(
        {
            "items": items,
            "pagination": {
                "page": page,
                "limit": limit,
                "total": total,
                "pages": pages,
                "has_next": page * limit < total,
            },
        },
        message="OK",
    )
