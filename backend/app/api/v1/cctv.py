"""CCTV API routes."""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query, Request, status
from pymongo.database import Database

from app.api.deps import CurrentUser, require_permission
from app.core.errors import ValidationError, success
from app.core.rbac import Permission
from app.config import settings
from app.db.mongo import get_db
from app.schemas.cctv import CctvCreate, CctvUpdate
from app.services import audit_service, cctv_service

router = APIRouter(prefix="/cctvs", tags=["CCTV"])

# One status, or several separated by commas, e.g. "ACTIVE,MAINTENANCE".
_STATUS_PATTERN = r"^(ACTIVE|INACTIVE|MAINTENANCE)(,(ACTIVE|INACTIVE|MAINTENANCE))*$"


def _pagination(page: int, limit: int) -> tuple[int, int]:
    if page < 1:
        raise ValidationError("page must be >= 1.")
    if limit < 1 or limit > settings.MAX_PAGE_SIZE:
        raise ValidationError(f"limit must be between 1 and {settings.MAX_PAGE_SIZE}.")
    return (page - 1) * limit, limit


def _pagination_meta(page: int, limit: int, total: int) -> dict:
    pages = (total + limit - 1) // limit if limit else 0
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "pages": pages,
        "has_next": page * limit < total,
    }


@router.get("", status_code=status.HTTP_200_OK)
def list_cctvs(
    page: int = Query(1, ge=1),
    limit: int = Query(settings.DEFAULT_PAGE_SIZE, ge=1, le=settings.MAX_PAGE_SIZE),
    search: Optional[str] = Query(None, max_length=200),
    status_filter: Optional[str] = Query(None, alias="status", max_length=64, pattern=_STATUS_PATTERN),
    type: Optional[str] = Query(None, max_length=32, pattern=r"^(Dome|Bullet|PTZ)(,(Dome|Bullet|PTZ))*$"),
    region: Optional[str] = Query(None, max_length=120),
    township: Optional[str] = Query(None, max_length=120),
    tag: Optional[str] = Query(
        None,
        max_length=64,
        pattern=r"^(?:(?:ALPRS|FRS|CPCS|ARDS)(?:,(?:ALPRS|FRS|CPCS|ARDS))*|All)$",
    ),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    user: CurrentUser = Depends(require_permission(Permission.CCTV_READ)),
    db: Database = Depends(get_db),
):
    from datetime import datetime

    skip, take = _pagination(page, limit)

    def _parse(value: Optional[str]) -> Optional[datetime]:
        if not value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            raise ValidationError("Invalid date format. Use ISO 8601.")

    # Enforce authorization: filter CCTV by user's authorized scope
    # The service layer will handle the actual MongoDB query filtering
    docs, total = cctv_service.list_cctvs(
        db,
        search=search,
        status=status_filter,
        type=type,
        region=region,
        township=township,
        tag=tag,
        date_from=_parse(date_from),
        date_to=_parse(date_to),
        skip=skip,
        limit=take,
        user=user,  # Pass user for scope filtering
    )
    items = [cctv_service.serialize_cctv(d) for d in docs]
    return success(
        {"items": items, "pagination": _pagination_meta(page, limit, total)},
        message="OK",
    )


@router.get("/map", status_code=status.HTTP_200_OK)
def map_viewport(
    min_lat: float = Query(..., ge=-90, le=90),
    max_lat: float = Query(..., ge=-90, le=90),
    min_lng: float = Query(..., ge=-180, le=180),
    max_lng: float = Query(..., ge=-180, le=180),
    zoom: Optional[float] = Query(None, ge=0, le=24),
    status_filter: Optional[str] = Query(None, alias="status", max_length=64, pattern=_STATUS_PATTERN),
    limit: int = Query(2000, ge=1, le=5000),
    user: CurrentUser = Depends(require_permission(Permission.CCTV_READ)),
    db: Database = Depends(get_db),
):
    if min_lat >= max_lat or min_lng >= max_lng:
        raise ValidationError("Invalid viewport bounds.")

    # The service layer will enforce scope filtering in the MongoDB query
    docs = cctv_service.map_viewport(
        db,
        min_lat=min_lat,
        max_lat=max_lat,
        min_lng=min_lng,
        max_lng=max_lng,
        status=status_filter,
        limit=limit,
        user=user,  # Pass user for scope filtering
    )
    markers = [cctv_service.serialize_marker(d) for d in docs]
    return success({"items": markers, "count": len(markers)}, message="OK")


@router.get("/nearby", status_code=status.HTTP_200_OK)
def nearby(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_meters: float = Query(1000, gt=0, le=50000),
    limit: int = Query(100, ge=1, le=500),
    user: CurrentUser = Depends(require_permission(Permission.CCTV_READ)),
    db: Database = Depends(get_db),
):
    docs = cctv_service.nearby(
        db,
        latitude=latitude,
        longitude=longitude,
        radius_meters=radius_meters,
        limit=limit,
        user=user,  # Pass user for scope filtering
    )
    markers = [cctv_service.serialize_marker(d) for d in docs]
    return success({"items": markers, "count": len(markers)}, message="OK")


@router.get("/stats", status_code=status.HTTP_200_OK)
def stats(
    user: CurrentUser = Depends(require_permission(Permission.CCTV_READ)),
    db: Database = Depends(get_db),
):
    return success(cctv_service.global_stats(db, user=user), message="OK")


@router.get("/areas", status_code=status.HTTP_200_OK)
def areas(
    user: CurrentUser = Depends(require_permission(Permission.CCTV_READ)),
    db: Database = Depends(get_db),
):
    """Region -> townships used by CCTV records the caller can see."""
    return success({"regions": cctv_service.list_areas(db, user)}, message="OK")


@router.post("", status_code=status.HTTP_201_CREATED)
def create_cctv(
    payload: CctvCreate,
    request: Request,
    user: CurrentUser = Depends(require_permission(Permission.CCTV_CREATE)),
    db: Database = Depends(get_db),
):
    doc = cctv_service.create_cctv(db, payload, user=user)
    audit_service.record(
        db,
        action=audit_service.CCTV_CREATED,
        user=user,
        resource_type="CCTV",
        resource_id=str(doc["_id"]),
        cctv=doc,
        request=request,
        metadata={"created_fields": sorted(payload.model_fields_set)},
    )
    return success(cctv_service.serialize_cctv(doc), message="CCTV created.")


@router.get("/{cctv_id}", status_code=status.HTTP_200_OK)
def get_cctv(
    cctv_id: str,
    request: Request,
    user: CurrentUser = Depends(require_permission(Permission.CCTV_READ)),
    db: Database = Depends(get_db),
):
    from app.core.errors import NotFoundError

    doc = cctv_service.get_by_id(db, cctv_id, user=user)
    if not doc:
        raise NotFoundError("CCTV not found.")
    audit_service.record(
        db,
        action=audit_service.CCTV_VIEWED,
        user=user,
        cctv=doc,
        resource_type="CCTV",
        resource_id=str(doc["_id"]),
        request=request,
    )
    return success(
        cctv_service.serialize_cctv(doc, include_credentials=True), message="OK"
    )


@router.put("/{cctv_id}", status_code=status.HTTP_200_OK)
def update_cctv(
    cctv_id: str,
    payload: CctvUpdate,
    request: Request,
    user: CurrentUser = Depends(require_permission(Permission.CCTV_UPDATE)),
    db: Database = Depends(get_db),
):
    doc = cctv_service.update_cctv(db, cctv_id, payload, user=user)
    audit_service.record(
        db,
        action=audit_service.CCTV_UPDATED,
        user=user,
        resource_type="CCTV",
        resource_id=str(doc["_id"]),
        cctv=doc,
        request=request,
        metadata={"changed_fields": sorted(payload.model_fields_set)},
    )
    # The service layer already enforced authorization in update_cctv
    return success(cctv_service.serialize_cctv(doc), message="CCTV updated.")



@router.delete("/{cctv_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_cctv(
    cctv_id: str,
    request: Request,
    user: CurrentUser = Depends(require_permission(Permission.CCTV_DELETE)),
    db: Database = Depends(get_db),
):
    doc = cctv_service.get_by_id(db, cctv_id, user=user)
    if not doc:
        from app.core.errors import NotFoundError
        raise NotFoundError("CCTV not found.")
    # Remove the record first: if this fails nothing is lost, whereas deleting
    # the images first would leave a record pointing at missing objects.
    cctv_service.delete_cctv(db, cctv_id, user=user)

    # Best-effort cleanup of associated objects.
    from app.services import storage_service

    for img in doc.get("images", []):
        if img.get("object_key"):
            storage_service.remove_object(img["object_key"])
        if img.get("thumbnail_key"):
            storage_service.remove_object(img["thumbnail_key"])
    audit_service.record(
        db,
        action=audit_service.CCTV_DELETED,
        user=user,
        resource_type="CCTV",
        resource_id=str(doc["_id"]),
        cctv=doc,
        request=request,
    )
    return None
