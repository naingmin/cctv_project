"""CCTV persistence and geospatial queries."""
from __future__ import annotations

import base64
import os
import re
from datetime import datetime, timezone
from typing import Any, Optional
from urllib.parse import quote

from bson import ObjectId
from bson.errors import InvalidId
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from pymongo.database import Database
from pymongo.errors import DuplicateKeyError

from app.config import settings
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.core.rbac import Role
from app.schemas.cctv import CctvCreate, CctvUpdate
from app.services import storage_service


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


# ---------------------------------------------------------------------------
# Authorization scope
#
# Which CCTV records a user may see is expressed once, as a MongoDB filter,
# and reused by every read path (list, map, nearby, stats, detail). Scoped
# roles are deny-by-default: a regional admin or supervisor without an
# assigned region/township gets an error, never global access.
#
#   OVERALL_ADMIN / ADMIN : every record
#   REGIONAL_ADMIN        : records in their assigned region
#   SUPERVISOR            : records in their assigned region + sub-region
#   OPERATOR / USER       : records they created
#
# Role-level permissions (may this role update at all?) are enforced by the
# route dependencies in app.api.deps; this module only answers "which records".
# ---------------------------------------------------------------------------

_NO_SCOPE_MESSAGE = "Your account has no region assigned. Ask an administrator to assign one."
_CREDENTIAL_PREFIX = "enc:v1:"
_CREDENTIAL_AAD = b"cctv-credentials:v1"


def _credentials_key() -> bytes:
    encoded = settings.CCTV_CREDENTIALS_ENCRYPTION_KEY
    if not encoded:
        raise RuntimeError(
            "CCTV_CREDENTIALS_ENCRYPTION_KEY must be configured before "
            "saving or reading CCTV credentials."
        )
    key = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
    if len(key) != 32:
        raise RuntimeError(
            "CCTV_CREDENTIALS_ENCRYPTION_KEY must decode to exactly 32 bytes."
        )
    return key


def _encrypt_credential(value: Optional[str]) -> Optional[str]:
    if value is None or value == "":
        return None
    nonce = os.urandom(12)
    encrypted = AESGCM(_credentials_key()).encrypt(
        nonce, value.encode("utf-8"), _CREDENTIAL_AAD
    )
    encoded = base64.urlsafe_b64encode(nonce + encrypted).decode("ascii")
    return _CREDENTIAL_PREFIX + encoded


def _decrypt_credential(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    if not value.startswith(_CREDENTIAL_PREFIX):
        raise ValueError("Stored CCTV credential is not encrypted.")
    ciphertext = base64.urlsafe_b64decode(value[len(_CREDENTIAL_PREFIX):])
    plaintext = AESGCM(_credentials_key()).decrypt(
        ciphertext[:12], ciphertext[12:], _CREDENTIAL_AAD
    )
    return plaintext.decode("utf-8")


def _scope_value(user: Any, id_field: str, legacy_field: str) -> tuple[str, Any]:
    identifier = getattr(user, id_field, None)
    if identifier:
        return id_field, identifier
    value = getattr(user, legacy_field, None)
    return legacy_field, value


def scope_filter(user: Any) -> dict[str, Any]:
    """MongoDB filter of the records ``user`` may read. ``{}`` means all."""
    role = Role(user.role)
    if role.is_overall_admin:
        return {}
    if role.is_operator:
        return {"created_by": user.id}
    region_field, region = _scope_value(user, "region_id", "region")
    if role.is_regional_admin:
        if not region:
            raise ForbiddenError(_NO_SCOPE_MESSAGE)
        scope = {region_field: region}
        if region_field == "region":
            scope["region_id"] = None
        return scope
    if role.is_supervisor:
        sub_region_field, sub_region = _scope_value(
            user, "sub_region_id", "township"
        )
        if not region or not sub_region:
            raise ForbiddenError(
                "Your account has no region and sub-region assigned. "
                "Ask an administrator to assign them."
            )
        scope = {region_field: region, sub_region_field: sub_region}
        if region_field == "region":
            scope["region_id"] = None
        if sub_region_field == "township":
            scope["sub_region_id"] = None
        return scope
    raise ForbiddenError("You do not have permission to access CCTV records.")


def _restrict(query: dict[str, Any], user: Any) -> dict[str, Any]:
    """AND ``query`` with the user's scope, without clobbering its keys."""
    scope = scope_filter(user)
    if not scope:
        return query
    if not query:
        return scope
    return {"$and": [query, scope]}


def _in_scope(scope: dict[str, Any], values: dict[str, Any]) -> bool:
    return all(values.get(field) == expected for field, expected in scope.items())


def _check_cctv_access(user: Any, cctv: dict, action: str = "read") -> None:
    """Raise ForbiddenError unless ``user`` may read ``cctv``.

    Write actions additionally go through :func:`_check_cctv_write_access`.
    """
    if not _in_scope(scope_filter(user), cctv):
        raise ForbiddenError("This CCTV record is outside your authorized area.")
    if action != "read":
        _check_cctv_write_access(user, cctv)


def _check_cctv_write_access(user: Any, cctv: dict) -> None:
    """Raise ForbiddenError unless ``user`` may modify ``cctv``."""
    if not _in_scope(scope_filter(user), cctv):
        raise ForbiddenError("This CCTV record is outside your authorized area.")


def _check_target_in_scope(user: Any, values: dict[str, Any]) -> None:
    """Ensure a created/updated record still lies inside the user's scope.

    Stops a regional admin from creating a record in another region, or from
    moving one out of their region (or clearing its region to make it
    unscoped).
    """
    role = Role(user.role)
    if role.is_operator or role.is_overall_admin:
        return
    scope = scope_filter(user)
    if scope and not _in_scope(scope, values):
        allowed = ", ".join(f"{k}={v}" for k, v in scope.items())
        raise ForbiddenError(
            f"Records you create or edit must stay within your area ({allowed})."
        )


def primary_view_key(images: list) -> Optional[str]:
    """Object key of the image to represent a record in a list or marker."""
    if not images:
        return None
    for image in images:
        if image.get("image_type") == "CCTV_VIEW" and image.get("object_key"):
            return image["object_key"]
    for image in images:
        if image.get("object_key"):
            return image["object_key"]
    return None


def _presigned_view_url(images: list) -> Optional[str]:
    """Presigned GET URL for a record's primary image, if it has one.

    Signing is a local HMAC, so this costs no round trip to object storage and
    is safe to call for every record in a page of results.
    """
    key = primary_view_key(images)
    if not key:
        return None
    try:
        return storage_service.presigned_get_url(
            key, settings.PRESIGN_EXPIRE_SECONDS
        )
    except Exception:
        # A storage hiccup must not break the whole listing.
        return None


def to_geojson(longitude: float, latitude: float) -> dict:
    """Build a GeoJSON Point. NOTE: order is [longitude, latitude]."""
    return {"type": "Point", "coordinates": [longitude, latitude]}


def serialize_cctv(doc: dict, *, include_credentials: bool = False) -> dict:
    location = doc.get("location") or {}
    coords = location.get("coordinates") or [doc.get("longitude"), doc.get("latitude")]
    result = {
        "id": str(doc["_id"]),
        "cctv_id": doc["cctv_id"],
        "latitude": coords[1],
        "longitude": coords[0],
        "region_id": doc.get("region_id"),
        "sub_region_id": doc.get("sub_region_id"),
        "region": doc.get("region"),
        "township": doc.get("township"),
        "street": doc.get("street"),
        "direction": doc.get("direction"),
        "rtsp_port": doc.get("rtsp_port", 554),
        "tags": doc.get("tags", []),
        "status": doc.get("status", "ACTIVE"),
        "last_checked": doc.get("last_checked"),
        "type": doc.get("type"),
        "description": doc.get("description"),
        "images": doc.get("images", []),
        "view_image_url": _presigned_view_url(doc.get("images", [])),
        "created_by": doc.get("created_by"),
        "updated_by": doc.get("updated_by"),
        "created_at": doc.get("created_at"),
        "updated_at": doc.get("updated_at"),
    }
    if include_credentials:
        result.update(
            {
                "ip_address": _decrypt_credential(doc.get("ip_address")),
                "username": _decrypt_credential(doc.get("username")),
                "password": _decrypt_credential(doc.get("password")),
            }
        )
    return result


def serialize_marker(doc: dict) -> dict:
    location = doc.get("location") or {}
    coords = location.get("coordinates") or [doc.get("longitude"), doc.get("latitude")]
    return {
        "id": str(doc["_id"]),
        "cctv_id": doc["cctv_id"],
        "latitude": coords[1],
        "longitude": coords[0],
        "direction": doc.get("direction"),
        "status": doc.get("status", "ACTIVE"),
        "thumbnail_url": _presigned_view_url(doc.get("images", [])),
    }


def get_by_id(
    db: Database, cctv_id: str, *, user: Any = None
) -> Optional[dict]:
    try:
        oid = ObjectId(cctv_id)
    except InvalidId:
        return None
    query: dict[str, Any] = {"_id": oid}
    if user is not None:
        query = _restrict(query, user)
    return db.cctvs.find_one(query)


def get_by_business_id(db: Database, business_id: str) -> Optional[dict]:
    return db.cctvs.find_one({"cctv_id": business_id})


def create_cctv(db: Database, payload: CctvCreate, *, user: Any) -> dict:
    # The role's CCTV_CREATE permission is checked by the route; here the new
    # record must also fall inside the user's own area.
    _check_target_in_scope(
        user,
        {
            "region_id": payload.region_id,
            "sub_region_id": payload.sub_region_id,
            "region": payload.region,
            "township": payload.township,
        },
    )

    user_id = user.id
    now = _now()
    doc: dict[str, Any] = {
        "cctv_id": payload.cctv_id,
        "location": to_geojson(payload.longitude, payload.latitude),
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "region_id": payload.region_id,
        "sub_region_id": payload.sub_region_id,
        "region": payload.region,
        "township": payload.township,
        "street": payload.street,
        "direction": payload.direction,
        "ip_address": _encrypt_credential(payload.ip_address),
        "rtsp_port": payload.rtsp_port,
        "username": _encrypt_credential(payload.username),
        "password": _encrypt_credential(payload.password),
        "tags": payload.tags,
        "status": payload.status,
        "last_checked": None,
        "type": payload.type,
        "description": payload.description,
        "images": [],
        "created_by": user_id,
        "updated_by": user_id,
        "created_at": now,
        "updated_at": now,
    }
    try:
        result = db.cctvs.insert_one(doc)
    except DuplicateKeyError as exc:
        raise ConflictError("A CCTV with this ID already exists.") from exc
    doc["_id"] = result.inserted_id
    return doc


def update_cctv(
    db: Database, cctv_id: str, payload: CctvUpdate, *, user: Any
) -> dict:
    doc = get_by_id(db, cctv_id, user=user)
    if not doc:
        raise NotFoundError("CCTV not found.")

    # The record must be in scope now, and must still be after the update.
    _check_cctv_access(user, doc, "update")

    updates: dict[str, Any] = {}
    data = payload.model_dump(exclude_unset=True)

    if "cctv_id" in data and data["cctv_id"]:
        updates["cctv_id"] = data["cctv_id"]
    for field in (
        "region_id",
        "sub_region_id",
        "region",
        "township",
        "street",
        "direction",
        "ip_address",
        "rtsp_port",
        "username",
        "password",
        "tags",
        "status",
        "type",
        "description",
    ):
        if field in data:
            updates[field] = (
                _encrypt_credential(data[field])
                if field in {"ip_address", "username", "password"}
                else data[field]
            )
    if "latitude" in data and "longitude" in data:
        lat, lng = data["latitude"], data["longitude"]
        updates["latitude"] = lat
        updates["longitude"] = lng
        updates["location"] = to_geojson(lng, lat)

    if not updates:
        return doc

    _check_target_in_scope(
        user,
        {
            "region_id": updates.get("region_id", doc.get("region_id")),
            "sub_region_id": updates.get("sub_region_id", doc.get("sub_region_id")),
            "region": updates.get("region", doc.get("region")),
            "township": updates.get("township", doc.get("township")),
        },
    )

    updates["updated_by"] = user.id
    updates["updated_at"] = _now()
    try:
        result = db.cctvs.update_one(
            _restrict({"_id": doc["_id"]}, user), {"$set": updates}
        )
    except DuplicateKeyError as exc:
        raise ConflictError("A CCTV with this ID already exists.") from exc
    if result.matched_count != 1:
        raise NotFoundError("CCTV not found.")
    updated_doc = db.cctvs.find_one(_restrict({"_id": doc["_id"]}, user))
    if not updated_doc:
        raise NotFoundError("CCTV not found.")
    return updated_doc


def verify_rtsp_connection(
    ip_address: Optional[str],
    rtsp_port: Optional[int],
    username: Optional[str],
    password: Optional[str],
) -> bool:
    """Open the camera briefly and verify that it yields a video frame."""
    if not ip_address:
        return False

    import cv2

    authority = f"[{ip_address}]" if ":" in ip_address else ip_address
    if username:
        credentials = quote(username, safe="")
        if password:
            credentials += f":{quote(password, safe='')}"
        authority = f"{credentials}@{authority}"
    rtsp_url = f"rtsp://{authority}:{rtsp_port or 554}/Streaming/Channels/101"
    capture = cv2.VideoCapture(
        rtsp_url,
        cv2.CAP_FFMPEG,
        [
            cv2.CAP_PROP_OPEN_TIMEOUT_MSEC,
            5000,
            cv2.CAP_PROP_READ_TIMEOUT_MSEC,
            5000,
        ],
    )
    try:
        if not capture.isOpened():
            return False
        success, frame = capture.read()
        return bool(success and frame is not None)
    finally:
        capture.release()


def test_connection(db: Database, cctv_id: str, *, user: Any) -> tuple[dict, bool]:
    """Check a stored camera's RTSP stream and persist its operational state."""
    try:
        object_id = ObjectId(cctv_id)
    except InvalidId as exc:
        raise ValidationError(
            "cctv_id must be the CCTV MongoDB record ID (24-character ObjectId), "
            f"not its display ID: {cctv_id!r}."
        ) from exc

    query: dict[str, Any] = {"_id": object_id}
    if user is not None:
        query = _restrict(query, user)
    doc = db.cctvs.find_one(query)
    if not doc:
        raise NotFoundError(
            f"No CCTV record was found for MongoDB ID {cctv_id!r}, "
            "or it is outside your authorized scope."
        )
    _check_cctv_access(user, doc, "update")

    connected = verify_rtsp_connection(
        _decrypt_credential(doc.get("ip_address")),
        doc.get("rtsp_port", 554),
        _decrypt_credential(doc.get("username")),
        _decrypt_credential(doc.get("password")),
    )
    checked_at = _now()
    status = "ACTIVE" if connected else "INACTIVE"
    result = db.cctvs.update_one(
        _restrict({"_id": doc["_id"]}, user),
        {
            "$set": {
                "status": status,
                "last_checked": checked_at,
                "updated_at": checked_at,
                "updated_by": user.id,
            }
        },
    )
    if result.matched_count != 1:
        raise NotFoundError(
            f"CCTV record {cctv_id!r} was removed or is no longer accessible."
        )
    updated_doc = db.cctvs.find_one(
        _restrict({"_id": object_id}, user)
    )
    if not updated_doc:
        raise NotFoundError(
            f"CCTV record {cctv_id!r} was removed or is no longer accessible."
        )
    return updated_doc, connected


def delete_cctv(db: Database, cctv_id: str, *, user: Any) -> dict:
    doc = get_by_id(db, cctv_id, user=user)
    if not doc:
        raise NotFoundError("CCTV not found.")

    # Authorization is checked by the caller (API route) before this runs.
    result = db.cctvs.delete_one(_restrict({"_id": doc["_id"]}, user))
    if result.deleted_count != 1:
        raise NotFoundError("CCTV not found.")
    return doc


def _status_condition(status: str) -> Any:
    """Mongo condition for a status filter: one value or a comma list."""
    values = sorted({s.strip() for s in status.split(",") if s.strip()})
    return values[0] if len(values) == 1 else {"$in": values}


def _build_filter(
    *,
    search: Optional[str],
    status: Optional[str],
    region: Optional[str],
    township: Optional[str],
    date_from: Optional[datetime],
    date_to: Optional[datetime],
    type: Optional[str] = None,
    tag: Optional[str] = None,
) -> dict:
    query: dict[str, Any] = {}
    if search and search.strip():
        # Escaped: search text is matched literally, never as a pattern, so
        # it cannot inject regex syntax or trigger catastrophic backtracking.
        regex = {"$regex": re.escape(search.strip()), "$options": "i"}
        query["$or"] = [
            {"cctv_id": regex},
            {"type": regex},
            {"region": regex},
            {"township": regex},
            {"street": regex},
            {"description": regex},
        ]
    if status:
        query["status"] = _status_condition(status)
    if type:
        type_values = sorted({t.strip() for t in type.split(",") if t.strip()})
        query["type"] = type_values[0] if len(type_values) == 1 else {"$in": type_values}
    if region:
        query["region"] = region
    if township:
        query["township"] = township
    if tag and tag.strip().upper() != "ALL":
        tags = [value.strip() for value in tag.split(",")]
        query["tags"] = tags[0] if len(tags) == 1 else {"$in": tags}
    if date_from or date_to:
        rng: dict[str, Any] = {}
        if date_from:
            rng["$gte"] = date_from
        if date_to:
            rng["$lte"] = date_to
        query["created_at"] = rng
    return query


def list_cctvs(
    db: Database,
    *,
    search: Optional[str],
    status: Optional[str],
    region: Optional[str],
    township: Optional[str],
    date_from: Optional[datetime],
    date_to: Optional[datetime],
    skip: int,
    limit: int,
    user: Any,
    type: Optional[str] = None,
    tag: Optional[str] = None,
) -> tuple[list[dict], int]:
    """Paginated records matching the filters, limited to the user's scope.

    Client filters are combined with the scope using ``$and``, so a client can
    narrow its view but never widen it.
    """
    query = _restrict(
        _build_filter(
            search=search,
            status=status,
            type=type,
            region=region,
            township=township,
            tag=tag,
            date_from=date_from,
            date_to=date_to,
        ),
        user,
    )
    total = db.cctvs.count_documents(query)
    cursor = db.cctvs.find(query).sort("created_at", -1).skip(skip).limit(limit)
    return list(cursor), total


def map_viewport(
    db: Database,
    *,
    min_lat: float,
    max_lat: float,
    min_lng: float,
    max_lng: float,
    status: Optional[str],
    limit: int,
    user: Any,
) -> list[dict]:
    """Lightweight markers inside the viewport, limited to the user's scope."""
    geometry = {
        "type": "Polygon",
        "coordinates": [
            [
                [min_lng, min_lat],
                [max_lng, min_lat],
                [max_lng, max_lat],
                [min_lng, max_lat],
                [min_lng, min_lat],
            ]
        ],
    }
    query: dict[str, Any] = {"location": {"$geoWithin": {"$geometry": geometry}}}
    if status:
        query["status"] = _status_condition(status)
    # Plain key merge (not $and) keeps the geo predicate top-level; scope
    # keys (region/township) never collide with location/status.
    query.update(scope_filter(user))
    return list(db.cctvs.find(query).limit(limit))


def nearby(
    db: Database,
    *,
    latitude: float,
    longitude: float,
    radius_meters: float,
    limit: int,
    user: Any,
) -> list[dict]:
    query: dict[str, Any] = {
        "location": {
            "$near": {
                "$geometry": to_geojson(longitude, latitude),
                "$maxDistance": radius_meters,
            }
        }
    }
    # $near must stay a top-level predicate (it cannot sit inside $and).
    query.update(scope_filter(user))
    return list(db.cctvs.find(query).limit(limit))


def global_stats(db: Database, user: Any) -> dict:
    """Dashboard statistics via aggregation, limited to the user's scope.

    User counts are only included for roles allowed to read users; others
    get 0 so the response shape stays the same for every client.
    """
    from app.core.rbac import Permission, role_has_permission

    now = _now()
    start_of_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    start_of_month = start_of_today.replace(day=1)

    scope = scope_filter(user)
    pipeline: list[dict[str, Any]] = []
    if scope:
        pipeline.append({"$match": scope})
    pipeline.append({"$group": {"_id": "$status", "count": {"$sum": 1}}})

    status_counts = {doc["_id"]: doc["count"] for doc in db.cctvs.aggregate(pipeline)}
    added_today = db.cctvs.count_documents(
        {**scope, "created_at": {"$gte": start_of_today}}
    )
    added_month = db.cctvs.count_documents(
        {**scope, "created_at": {"$gte": start_of_month}}
    )

    if role_has_permission(Role(user.role), Permission.USER_READ):
        from app.services import user_service

        user_scope = user_service.user_scope_filter(user)
        total_users = db.users.count_documents(user_scope)
        active_query = (
            {"$and": [user_scope, {"is_active": True}]}
            if user_scope
            else {"is_active": True}
        )
        active_users = db.users.count_documents(active_query)
    else:
        total_users = active_users = 0

    return {
        "total_cctv": sum(status_counts.values()),
        "active_cctv": status_counts.get("ACTIVE", 0),
        "inactive_cctv": status_counts.get("INACTIVE", 0),
        "maintenance_cctv": status_counts.get("MAINTENANCE", 0),
        "added_today": added_today,
        "added_this_month": added_month,
        "total_users": total_users,
        "active_users": active_users,
    }


def list_areas(db: Database, user: Any) -> dict[str, list[str]]:
    """Regions in use, each with its townships, limited to the user's scope.

    Lets the app suggest existing names when assigning an area to a user;
    scoping matches records by exact name, so a typo would silently hide
    every record from that user.
    """
    pipeline: list[dict[str, Any]] = []
    scope = scope_filter(user)
    if scope:
        pipeline.append({"$match": scope})
    pipeline += [
        {"$match": {"region": {"$nin": [None, ""]}}},
        {"$group": {"_id": "$region", "townships": {"$addToSet": "$township"}}},
    ]
    areas = {
        doc["_id"]: sorted(t for t in doc.get("townships", []) if t)
        for doc in db.cctvs.aggregate(pipeline)
    }
    return dict(sorted(areas.items()))


def add_image_metadata(
    db: Database, cctv_obj_id: ObjectId, image: dict, *, user: Any
) -> None:
    result = db.cctvs.update_one(
        _restrict({"_id": cctv_obj_id}, user),
        {"$push": {"images": image}, "$set": {"updated_at": _now()}},
    )
    if result.matched_count != 1:
        raise NotFoundError("CCTV not found.")


def remove_image_metadata(
    db: Database, cctv_obj_id: ObjectId, image_id: str, *, user: Any
) -> Optional[dict]:
    query = _restrict({"_id": cctv_obj_id}, user)
    doc = db.cctvs.find_one(query)
    if not doc:
        return None
    images = doc.get("images", [])
    target = next((img for img in images if img.get("id") == image_id), None)
    if target is None:
        return None
    result = db.cctvs.update_one(
        query,
        {"$pull": {"images": {"id": image_id}}, "$set": {"updated_at": _now()}},
    )
    return target if result.matched_count == 1 else None
