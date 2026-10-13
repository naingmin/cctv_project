"""Object storage service backed by MinIO (S3-compatible API).

Design notes
------------

Two boto3 clients are kept deliberately:

* ``_get_client()`` points at ``MINIO_ENDPOINT`` and performs the real S3 calls
  (head, delete, put). In Docker this is the internal service address.
* ``_get_presign_client()`` points at ``MINIO_PUBLIC_ENDPOINT`` and is used
  *only* to sign URLs. Presigned URLs are fetched by the client, so they must
  carry an address the client can reach, not one only this process can.

Both use path-style addressing, which MinIO requires for bucket names that are
not DNS-compatible, and which avoids virtual-host bucket DNS lookups entirely.
"""

from __future__ import annotations

import uuid
from typing import Optional

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.config import settings
from app.core.errors import AppError, NotFoundError, ValidationError
from app.core.logging import get_logger

logger = get_logger(__name__)

ALLOWED_CONTENT_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}

_client = None
_presign_client = None


def _build_client(endpoint: str):
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=settings.MINIO_ACCESS_KEY,
        aws_secret_access_key=settings.MINIO_SECRET_KEY,
        region_name=settings.MINIO_REGION,
        use_ssl=settings.MINIO_USE_SSL,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def _get_client():
    global _client
    if _client is None:
        _client = _build_client(settings.minio_endpoint)
    return _client


def _get_presign_client():
    global _presign_client
    if _presign_client is None:
        _presign_client = _build_client(settings.minio_public_endpoint)
    return _presign_client


def reset_clients() -> None:
    """Drop cached clients. Intended for tests and config reloads."""
    global _client, _presign_client
    _client = None
    _presign_client = None


def ensure_bucket() -> None:
    """Create the bucket if it does not exist yet.

    Safe to call on every boot: creating an existing bucket raises, which we
    treat as success.
    """
    client = _get_client()
    bucket = settings.MINIO_BUCKET
    try:
        client.head_bucket(Bucket=bucket)
        return
    except ClientError:
        pass

    try:
        client.create_bucket(Bucket=bucket)
        logger.info("Created object storage bucket '%s'.", bucket)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code")
        if code in {"BucketAlreadyOwnedByYou", "BucketAlreadyExists"}:
            return
        raise
    except Exception:
        # Surface as a warning rather than blocking startup; the presign
        # endpoint will fail loudly if the bucket is genuinely missing.
        logger.warning("Could not ensure object storage bucket '%s'.", bucket)


def validate_content_type(content_type: str, filename: str) -> str:
    content_type = (content_type or "").lower().strip()
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise ValidationError(
            "Unsupported image type. Allowed: JPEG, PNG, WEBP."
        )
    ext = ("." + filename.rsplit(".", 1)[-1].lower()) if "." in filename else ""
    if ext and ext not in ALLOWED_EXTENSIONS:
        raise ValidationError("Unsupported file extension.")
    return content_type


def build_object_key(cctv_id: str, image_type: str, ext: str) -> str:
    """Build a server-controlled, UUID-based object key."""
    safe_id = "".join(c for c in cctv_id if c.isalnum() or c in "-_")[:64]
    folder = "view" if image_type == "CCTV_VIEW" else "environment"
    return f"cctv/{safe_id}/{folder}/{uuid.uuid4().hex}{ext}"


def build_thumbnail_key(cctv_id: str, ext: str) -> str:
    safe_id = "".join(c for c in cctv_id if c.isalnum() or c in "-_")[:64]
    return f"cctv/{safe_id}/thumbnails/{uuid.uuid4().hex}{ext}"


def presigned_put_url(
    object_key: str, expires_seconds: int, content_type: Optional[str] = None
) -> str:
    """Return a SigV4-signed PUT URL for direct-to-storage upload.

    ``content_type`` is signed into the request so the stored object's
    Content-Type matches what the client declared, and MinIO rejects a
    mismatched upload rather than storing mislabelled bytes.
    """
    params: dict = {"Bucket": settings.MINIO_BUCKET, "Key": object_key}
    if content_type:
        params["ContentType"] = content_type
    return _get_presign_client().generate_presigned_url(
        "put_object",
        Params=params,
        ExpiresIn=expires_seconds,
    )


def presigned_get_url(object_key: str, expires_seconds: int) -> str:
    """Return a SigV4-signed GET URL for reading an object."""
    return _get_presign_client().generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.MINIO_BUCKET, "Key": object_key},
        ExpiresIn=expires_seconds,
    )


def object_exists(object_key: str) -> bool:
    try:
        _get_client().head_object(Bucket=settings.MINIO_BUCKET, Key=object_key)
        return True
    except ClientError:
        return False
    except BotoCoreError as exc:
        # Storage unreachable. Treated as "cannot confirm", which surfaces as a
        # failed upload rather than a 500.
        logger.warning("Object storage unreachable checking '%s': %s", object_key, exc)
        return False


def get_object_size(object_key: str) -> int:
    try:
        response = _get_client().head_object(
            Bucket=settings.MINIO_BUCKET, Key=object_key
        )
        return int(response.get("ContentLength", 0))
    except ClientError:
        return 0
    except BotoCoreError as exc:
        logger.warning("Object storage unreachable sizing '%s': %s", object_key, exc)
        return 0


def remove_object(object_key: str) -> None:
    """Delete an object, tolerating one that is already gone.

    Failures are logged rather than raised: the caller has usually already
    dropped the database record, so the object would be orphaned either way.
    """
    try:
        _get_client().delete_object(Bucket=settings.MINIO_BUCKET, Key=object_key)
    except Exception as exc:
        logger.warning(
            "Failed to remove object '%s' (%s); it may need manual cleanup.",
            object_key,
            exc,
        )


def save_object(
    object_key: str, data: bytes, content_type: Optional[str] = None
) -> None:
    """Write bytes directly to object storage.

    Not used by the HTTP upload path (clients PUT to their presigned URL), but
    kept for maintenance scripts and tests.
    """
    extra = {"ContentType": content_type} if content_type else {}
    _get_client().put_object(
        Bucket=settings.MINIO_BUCKET, Key=object_key, Body=data, **extra
    )


def read_object(object_key: str) -> bytes:
    """Read bytes directly from object storage."""
    try:
        response = _get_client().get_object(
            Bucket=settings.MINIO_BUCKET, Key=object_key
        )
        return response["Body"].read()
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code")
        if code in {"NoSuchKey", "404", "NotFound"}:
            raise NotFoundError("File not found.") from exc
        raise AppError(f"Object storage error: {code or 'unknown'}") from exc