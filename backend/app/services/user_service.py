"""User persistence and business logic."""
from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from pymongo.database import Database
from pymongo.errors import DuplicateKeyError

from app.core.errors import ConflictError, ForbiddenError, NotFoundError, ValidationError
from app.core.rbac import Role
from app.core.security import hash_password, validate_password_strength
from app.schemas.user import UserCreate, UserUpdate


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


#: Stored role values that mean "full administrator". ADMIN is the legacy
#: name the mobile app uses; OVERALL_ADMIN is the hierarchical name.
ADMIN_ROLE_VALUES = (Role.ADMIN.value, Role.OVERALL_ADMIN.value)


def is_admin_doc(doc: dict) -> bool:
    return doc.get("role") in ADMIN_ROLE_VALUES


def _clean(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    value = value.strip()
    return value or None


def validate_scope(role: Role, region: Optional[str], township: Optional[str]) -> None:
    """Scoped roles must have the area they are restricted to.

    Without this check a regional admin or supervisor could be saved with no
    region, which used to silently grant access to every record.
    """
    if role == Role.REGIONAL_ADMIN and not region:
        raise ValidationError("A Regional Administrator must be assigned a region.")
    if role == Role.SUPERVISOR and (not region or not township):
        raise ValidationError(
            "A Supervisor must be assigned both a region and a township."
        )


def _user_scope_values(user: object) -> tuple[str, str, Optional[str], Optional[str]]:
    region_id = getattr(user, "region_id", None)
    region = getattr(user, "region", None)
    sub_region_id = getattr(user, "sub_region_id", None)
    township = getattr(user, "township", None)
    return (
        "region_id" if region_id else "region",
        "sub_region_id" if sub_region_id else "township",
        region_id or region,
        sub_region_id or township,
    )


def _managed_roles(actor: object) -> tuple[str, ...]:
    role = Role(actor.role)
    if role.is_overall_admin:
        return tuple(item.value for item in Role)
    if role.is_regional_admin:
        return (Role.SUPERVISOR.value, Role.OPERATOR.value, Role.USER.value)
    if role.is_supervisor:
        return (Role.OPERATOR.value, Role.USER.value)
    return ()


def user_scope_filter(actor: object) -> dict:
    """Database-level filter for users this actor may manage."""
    role = Role(actor.role)
    if role.is_overall_admin:
        return {}
    if not (role.is_regional_admin or role.is_supervisor):
        raise ForbiddenError("You cannot access user management.")
    region_field, sub_region_field, region, sub_region = _user_scope_values(actor)
    if not region or (role.is_supervisor and not sub_region):
        raise ForbiddenError("Your account has no complete management scope assigned.")
    conditions: list[dict] = [
        {region_field: region},
        {"role": {"$in": list(_managed_roles(actor))}},
    ]
    if region_field == "region":
        conditions.append({"region_id": None})
    if role.is_supervisor:
        conditions.append({sub_region_field: sub_region})
        if sub_region_field == "township":
            conditions.append({"sub_region_id": None})
    return {"$and": conditions}


def validate_user_assignment(
    actor: object,
    *,
    role: Role,
    region_id: Optional[str],
    sub_region_id: Optional[str],
    region: Optional[str],
    township: Optional[str],
) -> None:
    """Prevent scoped administrators from creating or promoting users outside scope."""
    actor_role = Role(actor.role)
    if actor_role.is_overall_admin:
        return
    if role.value not in _managed_roles(actor):
        raise ForbiddenError("You cannot assign or manage this role.")
    region_field, sub_region_field, actor_region, actor_sub_region = (
        _user_scope_values(actor)
    )
    if region_field == "region_id":
        requested_region = region_id
        if getattr(actor, "region", None) and region and region != actor.region:
            raise ForbiddenError("You can manage users only within your assigned region.")
    else:
        requested_region = region
        if region_id:
            raise ForbiddenError(
                "A region ID cannot be assigned without an administrator-provided scope ID."
            )
    if not actor_region or requested_region != actor_region:
        raise ForbiddenError("You can manage users only within your assigned region.")
    if sub_region_field == "sub_region_id":
        requested_sub_region = sub_region_id
        if (
            getattr(actor, "township", None)
            and township
            and township != actor.township
        ):
            raise ForbiddenError(
                "You can manage operators only within your assigned sub-region."
            )
    else:
        requested_sub_region = township
        if sub_region_id:
            raise ForbiddenError(
                "A sub-region ID cannot be assigned without an administrator-provided scope ID."
            )
    if actor_role.is_supervisor and (
        not actor_sub_region or requested_sub_region != actor_sub_region
    ):
        raise ForbiddenError(
            "You can manage operators only within your assigned sub-region."
        )


def serialize_user(doc: dict) -> dict:
    return {
        "id": str(doc["_id"]),
        "username": doc["username"],
        "email": doc["email"],
        "full_name": doc.get("full_name", ""),
        "role": doc.get("role", Role.USER.value),
        "is_active": doc.get("is_active", True),
        "region": doc.get("region"),
        "township": doc.get("township"),
        "region_id": doc.get("region_id"),
        "sub_region_id": doc.get("sub_region_id"),
        "created_at": doc.get("created_at"),
        "updated_at": doc.get("updated_at"),
        "last_login_at": doc.get("last_login_at"),
    }


def get_by_id(
    db: Database, user_id: str, *, actor: object = None
) -> Optional[dict]:
    try:
        oid = ObjectId(user_id)
    except Exception:
        return None
    query: dict = {"_id": oid}
    if actor is not None:
        scope = user_scope_filter(actor)
        query = {"$and": [query, scope]} if scope else query
    return db.users.find_one(query)


def get_by_username_or_email(db: Database, identifier: str) -> Optional[dict]:
    identifier = identifier.strip()
    return db.users.find_one(
        {"$or": [{"username": identifier}, {"email": identifier.lower()}]}
    )


def count_admins(db: Database) -> int:
    """Active full administrators, under either role name."""
    return db.users.count_documents(
        {"role": {"$in": list(ADMIN_ROLE_VALUES)}, "is_active": True}
    )


def create_user(
    db: Database, payload: UserCreate, *, actor: object = None
) -> dict:
    try:
        validate_password_strength(payload.password)
    except ValueError as exc:
        raise ValidationError(str(exc)) from exc

    region = _clean(payload.region)
    township = _clean(payload.township)
    region_id = _clean(payload.region_id)
    sub_region_id = _clean(payload.sub_region_id)
    validate_scope(
        payload.role, region or region_id, township or sub_region_id
    )
    if actor is not None:
        validate_user_assignment(
            actor,
            role=payload.role,
            region_id=region_id,
            sub_region_id=sub_region_id,
            region=region,
            township=township,
        )

    now = _now()
    doc = {
        "username": payload.username.strip(),
        "email": payload.email.lower(),
        "password_hash": hash_password(payload.password),
        "full_name": payload.full_name.strip(),
        "role": payload.role.value,
        "region": region,
        "township": township,
        "region_id": region_id,
        "sub_region_id": sub_region_id,
        "is_active": payload.is_active,
        "token_version": 1,
        "created_at": now,
        "updated_at": now,
        "last_login_at": None,
    }
    try:
        result = db.users.insert_one(doc)
    except DuplicateKeyError as exc:
        raise ConflictError("Username or email already exists.") from exc
    doc["_id"] = result.inserted_id
    return doc


def ensure_default_admin(
    db: Database, *, username: str, email: str, password: str, full_name: str
) -> None:
    """Create the initial admin if no users exist yet."""
    if db.users.count_documents({}) > 0:
        return
    if len(password) < 8:
        raise ValidationError("Default admin password is too short.")
    create_user(
        db,
        UserCreate(
            username=username,
            email=email,
            full_name=full_name,
            role=Role.ADMIN,
            is_active=True,
            password=password,
        ),
    )


def list_users(
    db: Database,
    *,
    search: Optional[str],
    role: Optional[str],
    is_active: Optional[bool],
    skip: int,
    limit: int,
    actor: object,
) -> tuple[list[dict], int]:
    query: dict = {}
    if search and search.strip():
        regex = {"$regex": re.escape(search.strip()), "$options": "i"}
        query["$or"] = [
            {"username": regex},
            {"email": regex},
            {"full_name": regex},
        ]
    if role:
        query["role"] = role
    if is_active is not None:
        query["is_active"] = is_active

    scope = user_scope_filter(actor)
    query = {"$and": [query, scope]} if query and scope else query or scope
    total = db.users.count_documents(query)
    cursor = (
        db.users.find(query)
        .sort("created_at", -1)
        .skip(skip)
        .limit(limit)
    )
    return list(cursor), total


def update_user(
    db: Database, user_id: str, payload: UserUpdate, *, actor: object = None
) -> dict:
    scope = user_scope_filter(actor) if actor is not None else {}
    query: dict = {"_id": ObjectId(user_id)} if ObjectId.is_valid(user_id) else {}
    query = {"$and": [query, scope]} if query and scope else query or scope
    doc = db.users.find_one(query) if query else None
    if not doc:
        raise NotFoundError("User not found.")

    data = payload.model_dump(exclude_unset=True)
    updates: dict = {}
    if payload.full_name is not None:
        updates["full_name"] = payload.full_name.strip()
    if payload.role is not None and payload.role.value != doc.get("role"):
        # Prevent demoting the last active admin.
        if (
            is_admin_doc(doc)
            and payload.role.value not in ADMIN_ROLE_VALUES
            and doc.get("is_active", True)
            and count_admins(db) <= 1
        ):
            raise ValidationError("Cannot demote the last active admin.")
        updates["role"] = payload.role.value
    if payload.is_active is not None and payload.is_active != doc.get("is_active", True):
        if (
            is_admin_doc(doc)
            and payload.is_active is False
            and count_admins(db) <= 1
        ):
            raise ValidationError("Cannot disable the last active admin.")
        updates["is_active"] = payload.is_active
    # Region/township can be set, or cleared by sending null explicitly.
    for field in ("region", "township"):
        if field in data and _clean(data[field]) != doc.get(field):
            updates[field] = _clean(data[field])
    for field in ("region_id", "sub_region_id"):
        if field in data and _clean(data[field]) != doc.get(field):
            updates[field] = _clean(data[field])

    # The resulting role + scope must be consistent. Checked only when one of
    # them changes, so an old inconsistent account can still be disabled.
    if {"role", "region", "township", "region_id", "sub_region_id"} & updates.keys():
        validate_scope(
            Role(updates.get("role", doc.get("role", Role.USER.value))),
            updates.get("region", doc.get("region"))
            or updates.get("region_id", doc.get("region_id")),
            updates.get("township", doc.get("township"))
            or updates.get("sub_region_id", doc.get("sub_region_id")),
        )
    if actor is not None:
        validate_user_assignment(
            actor,
            role=Role(updates.get("role", doc.get("role", Role.USER.value))),
            region_id=updates.get("region_id", doc.get("region_id")),
            sub_region_id=updates.get("sub_region_id", doc.get("sub_region_id")),
            region=updates.get("region", doc.get("region")),
            township=updates.get("township", doc.get("township")),
        )

    if not updates:
        return doc

    updates["updated_at"] = _now()
    # Invalidate existing sessions when anything that affects access changes.
    if {"role", "is_active", "region", "township", "region_id", "sub_region_id"} & updates.keys():
        updates["$inc"] = {"token_version": 1}

    inc = updates.pop("$inc", None)
    update_op: dict = {"$set": updates}
    if inc:
        update_op["$inc"] = inc

    result = db.users.update_one(
        {"$and": [{"_id": doc["_id"]}, scope]} if scope else {"_id": doc["_id"]},
        update_op,
    )
    if result.matched_count != 1:
        raise NotFoundError("User not found.")
    updated_doc = get_by_id(db, user_id, actor=actor)
    if not updated_doc:
        raise NotFoundError("User not found.")
    return updated_doc


def delete_user(db: Database, user_id: str, *, actor: object = None) -> None:
    scope = user_scope_filter(actor) if actor is not None else {}
    query: dict = {"_id": ObjectId(user_id)} if ObjectId.is_valid(user_id) else {}
    query = {"$and": [query, scope]} if query and scope else query or scope
    doc = db.users.find_one(query) if query else None
    if not doc:
        raise NotFoundError("User not found.")
    if is_admin_doc(doc) and doc.get("is_active", True) and count_admins(db) <= 1:
        raise ValidationError("Cannot delete the last active admin.")
    result = db.users.delete_one(
        {"$and": [{"_id": doc["_id"]}, scope]} if scope else {"_id": doc["_id"]}
    )
    if result.deleted_count != 1:
        raise NotFoundError("User not found.")


def set_password(db: Database, user_id: str, new_password: str) -> None:
    validate_password_strength(new_password)
    doc = get_by_id(db, user_id)
    if not doc:
        raise NotFoundError("User not found.")
    db.users.update_one(
        {"_id": doc["_id"]},
        {
            "$set": {
                "password_hash": hash_password(new_password),
                "updated_at": _now(),
            },
            "$inc": {"token_version": 1},
        },
    )


def touch_last_login(db: Database, user_id: str) -> None:
    db.users.update_one(
        {"_id": ObjectId(user_id)},
        {"$set": {"last_login_at": _now()}},
    )
