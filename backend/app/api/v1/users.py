"""Role- and scope-aware user management API routes."""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query, Request, status
from pymongo.database import Database

from app.api.deps import CurrentUser, require_permission
from app.config import settings
from app.core.errors import ValidationError, success
from app.core.rbac import Permission, Role
from app.db.mongo import get_db
from app.schemas.user import UserCreate, UserUpdate
from app.services import audit_service, user_service

router = APIRouter(prefix="/users", tags=["Users"])


def _meta(page: int, limit: int, total: int) -> dict:
    pages = (total + limit - 1) // limit if limit else 0
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "pages": pages,
        "has_next": page * limit < total,
    }


@router.get("", status_code=status.HTTP_200_OK)
def list_users(
    page: int = Query(1, ge=1),
    limit: int = Query(settings.DEFAULT_PAGE_SIZE, ge=1, le=settings.MAX_PAGE_SIZE),
    search: Optional[str] = Query(None, max_length=200),
    role: Optional[Role] = Query(None),
    is_active: Optional[bool] = Query(None),
    user: CurrentUser = Depends(require_permission(Permission.USER_READ)),
    db: Database = Depends(get_db),
):
    skip = (page - 1) * limit
    docs, total = user_service.list_users(
        db,
        search=search,
        role=role.value if role else None,
        is_active=is_active,
        skip=skip,
        limit=limit,
        actor=user,
    )
    items = [user_service.serialize_user(d) for d in docs]
    return success(
        {"items": items, "pagination": _meta(page, limit, total)}, message="OK"
    )


@router.post("", status_code=status.HTTP_201_CREATED)
def create_user(
    payload: UserCreate,
    request: Request,
    user: CurrentUser = Depends(require_permission(Permission.USER_CREATE)),
    db: Database = Depends(get_db),
):
    doc = user_service.create_user(db, payload, actor=user)
    audit_service.record(
        db,
        action=audit_service.USER_CREATED,
        user=user,
        resource_type="USER",
        resource_id=str(doc["_id"]),
        request=request,
        metadata={"username": doc["username"], "role": doc["role"]},
    )
    return success(user_service.serialize_user(doc), message="User created.")


@router.get("/{user_id}", status_code=status.HTTP_200_OK)
def get_user(
    user_id: str,
    actor: CurrentUser = Depends(require_permission(Permission.USER_READ)),
    db: Database = Depends(get_db),
):
    from app.core.errors import NotFoundError

    doc = user_service.get_by_id(db, user_id, actor=actor)
    if not doc:
        raise NotFoundError("User not found.")

    return success(user_service.serialize_user(doc), message="OK")


@router.put("/{user_id}", status_code=status.HTTP_200_OK)
def update_user(
    user_id: str,
    payload: UserUpdate,
    request: Request,
    actor: CurrentUser = Depends(require_permission(Permission.USER_UPDATE)),
    db: Database = Depends(get_db),
):
    target_doc = user_service.get_by_id(db, user_id, actor=actor)
    if not target_doc:
        from app.core.errors import NotFoundError
        raise NotFoundError("User not found.")

    # Administrators cannot change their own access: role, active status or
    # area. Compare against the stored value, not the resolved enum, so that
    # re-sending an unchanged "ADMIN" is not mistaken for a change.
    if user_id == actor.id:
        if payload.role is not None and payload.role.value != target_doc.get("role"):
            raise ValidationError("You cannot change your own role.")
        if payload.is_active is False:
            raise ValidationError("You cannot disable your own account.")

    doc = user_service.update_user(db, user_id, payload, actor=actor)

    action = audit_service.USER_UPDATED
    if payload.is_active is False:
        action = audit_service.USER_DISABLED
    if payload.role is not None:
        action = audit_service.ROLE_CHANGED

    audit_service.record(
        db,
        action=action,
        user=actor,
        resource_type="USER",
        resource_id=user_id,
        request=request,
        metadata={
            "role": doc.get("role"),
            "is_active": doc.get("is_active"),
        },
    )
    return success(user_service.serialize_user(doc), message="User updated.")


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: str,
    request: Request,
    actor: CurrentUser = Depends(require_permission(Permission.USER_DELETE)),
    db: Database = Depends(get_db),
):
    if user_id == actor.id:
        raise ValidationError("You cannot delete your own account.")

    target_doc = user_service.get_by_id(db, user_id, actor=actor)
    if not target_doc:
        from app.core.errors import NotFoundError
        raise NotFoundError("User not found.")

    # user_service refuses to delete the last active administrator.
    user_service.delete_user(db, user_id, actor=actor)
    audit_service.record(
        db,
        action=audit_service.USER_DELETED,
        user=actor,
        resource_type="USER",
        resource_id=user_id,
        request=request,
        metadata={"deleted": True},
    )
    return None
