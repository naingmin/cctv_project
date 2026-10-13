"""Image upload / download API routes."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request, status
from pymongo.database import Database

from app.api.deps import CurrentUser, require_permission
from app.config import settings
from app.core.errors import ForbiddenError, NotFoundError, ValidationError, success
from app.core.rbac import Permission
from app.db.mongo import get_db
from app.schemas.upload import (
    ImageCompleteRequest,
    ImageUrlResponse,
    ImageUrlsResponse,
    PresignRequest,
)
from app.services import audit_service, cctv_service, storage_service
from app.services.cctv_service import _check_cctv_access

router = APIRouter(tags=["Uploads"])

# Uploading adds evidence to a record without changing it, so it needs the
# image-upload permission plus read access to the record (Viewers included).
# Deleting an image destroys evidence, so it needs write access as well.
_can_upload = require_permission(Permission.CCTV_IMAGE_UPLOAD)
_can_read = require_permission(Permission.CCTV_READ)
_can_delete_image = require_permission(Permission.CCTV_IMAGE_DELETE)


def _check_thumbnail_key(cctv: dict, thumbnail_key: str | None) -> None:
    """A thumbnail must live under the record's own prefix, like the image.

    Otherwise a client could register any object in the bucket as its
    "thumbnail" and have it deleted along with the image later.
    """
    if thumbnail_key and not thumbnail_key.startswith(f"cctv/{cctv['cctv_id']}/"):
        raise ForbiddenError("Thumbnail key does not belong to this CCTV.")


@router.post("/uploads/presign", status_code=status.HTTP_200_OK)
def presign(
    payload: PresignRequest,
    user: CurrentUser = Depends(_can_upload),
    db: Database = Depends(get_db),
):
    cctv = cctv_service.get_by_id(db, payload.cctv_id, user=user)
    if not cctv:
        raise NotFoundError("CCTV not found.")

    content_type = storage_service.validate_content_type(
        payload.content_type, payload.filename
    )
    ext = storage_service.ALLOWED_CONTENT_TYPES[content_type]
    object_key = storage_service.build_object_key(
        cctv["cctv_id"], payload.image_type, ext
    )
    # Signed against the public endpoint so the client can PUT straight to
    # MinIO. Content type is part of the signature, which stops a client
    # storing bytes under a key whose extension claims a different format.
    upload_url = storage_service.presigned_put_url(
        object_key, settings.PRESIGN_EXPIRE_SECONDS, content_type=content_type
    )
    return success(
        {
            "upload_url": upload_url,
            "object_key": object_key,
            "thumbnail_key": None,
            "expires_in": settings.PRESIGN_EXPIRE_SECONDS,
        },
        message="Upload authorized.",
    )


@router.post(
    "/cctvs/{cctv_id}/images/complete",
    status_code=status.HTTP_201_CREATED,
)
def complete_image(
    cctv_id: str,
    payload: ImageCompleteRequest,
    request: Request,
    user: CurrentUser = Depends(_can_upload),
    db: Database = Depends(get_db),
):
    cctv = cctv_service.get_by_id(db, cctv_id, user=user)
    if not cctv:
        raise NotFoundError("CCTV not found.")

    # Validate the object key belongs to this CCTV to prevent cross-record abuse.
    expected_prefix = f"cctv/{cctv['cctv_id']}/"
    if not payload.object_key.startswith(expected_prefix):
        raise ForbiddenError("Object key does not belong to this CCTV.")
    _check_thumbnail_key(cctv, payload.thumbnail_key)

    storage_service.validate_content_type(payload.mime_type, payload.object_key)

    if not storage_service.object_exists(payload.object_key):
        raise ValidationError("Uploaded object was not found. Upload may have failed.")

    # The bytes went straight to MinIO, so the client-supplied size and MIME
    # type cannot be trusted: read them back off the stored object instead.
    actual_size = storage_service.get_object_size(payload.object_key)
    if actual_size > settings.max_image_bytes:
        storage_service.remove_object(payload.object_key)
        raise ValidationError("Image exceeds the maximum allowed size.")

    image = {
        "id": uuid.uuid4().hex,
        "image_type": payload.image_type,
        "object_key": payload.object_key,
        "thumbnail_key": payload.thumbnail_key,
        "file_size": actual_size or payload.file_size,
        "mime_type": payload.mime_type,
        "width": payload.width,
        "height": payload.height,
        "created_at": datetime.now(tz=timezone.utc),
    }
    cctv_service.add_image_metadata(db, cctv["_id"], image, user=user)
    audit_service.record(
        db,
        action=audit_service.IMAGE_UPLOADED,
        user=user,
        resource_type="CCTV_IMAGE",
        resource_id=image["id"],
        cctv=cctv,
        request=request,
        metadata={"image_type": payload.image_type},
    )
    return success(image, message="Image finalized.")


@router.get(
    "/cctvs/{cctv_id}/images/{image_id}/url",
    status_code=status.HTTP_200_OK,
)
def image_url(
    cctv_id: str,
    image_id: str,
    user: CurrentUser = Depends(_can_read),
    db: Database = Depends(get_db),
):
    cctv = cctv_service.get_by_id(db, cctv_id, user=user)
    if not cctv:
        raise NotFoundError("CCTV not found.")
    image = next(
        (img for img in cctv.get("images", []) if img.get("id") == image_id), None
    )
    if not image:
        raise NotFoundError("Image not found.")
    url = storage_service.presigned_get_url(
        image["object_key"], settings.PRESIGN_EXPIRE_SECONDS
    )
    payload = ImageUrlResponse(
        image_id=image_id, url=url, expires_in=settings.PRESIGN_EXPIRE_SECONDS
    )
    return success(payload.model_dump(), message="OK")


@router.get(
    "/cctvs/{cctv_id}/images/urls",
    status_code=status.HTTP_200_OK,
)
def image_urls(
    cctv_id: str,
    user: CurrentUser = Depends(_can_read),
    db: Database = Depends(get_db),
):
    """Resolve every image on a record in one round trip.

    Fetching a presigned URL per image means one request per thumbnail; this
    keeps list and detail screens to a single extra call.
    """
    cctv = cctv_service.get_by_id(db, cctv_id, user=user)
    if not cctv:
        raise NotFoundError("CCTV not found.")
    urls = {
        img["id"]: storage_service.presigned_get_url(
            img["object_key"], settings.PRESIGN_EXPIRE_SECONDS
        )
        for img in cctv.get("images", [])
        if img.get("object_key")
    }
    payload = ImageUrlsResponse(
        urls=urls, expires_in=settings.PRESIGN_EXPIRE_SECONDS
    )
    return success(payload.model_dump(), message="OK")


@router.delete(
    "/cctvs/{cctv_id}/images/{image_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_image(
    cctv_id: str,
    image_id: str,
    request: Request,
    user: CurrentUser = Depends(_can_delete_image),
    db: Database = Depends(get_db),
):
    cctv = cctv_service.get_by_id(db, cctv_id, user=user)
    if not cctv:
        raise NotFoundError("CCTV not found.")
    # Deleting an image modifies the record: needs write access to it.
    _check_cctv_access(user, cctv, "delete_image")

    removed = cctv_service.remove_image_metadata(
        db, cctv["_id"], image_id, user=user
    )
    if not removed:
        raise NotFoundError("Image not found.")

    storage_service.remove_object(removed["object_key"])
    if removed.get("thumbnail_key"):
        storage_service.remove_object(removed["thumbnail_key"])

    audit_service.record(
        db,
        action=audit_service.IMAGE_DELETED,
        user=user,
        resource_type="CCTV_IMAGE",
        resource_id=image_id,
        cctv=cctv,
        request=request,
    )
    return None
