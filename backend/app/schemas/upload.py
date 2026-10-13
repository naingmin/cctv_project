"""Upload / image schemas."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class PresignRequest(BaseModel):
    cctv_id: str = Field(min_length=1, max_length=64)
    image_type: str = Field(pattern=r"^(CCTV_VIEW|ENVIRONMENT)$")
    filename: str = Field(min_length=1, max_length=255)
    content_type: str = Field(min_length=3, max_length=100)


class PresignResponse(BaseModel):
    upload_url: str
    object_key: str
    thumbnail_key: Optional[str] = None
    expires_in: int


class ImageCompleteRequest(BaseModel):
    object_key: str = Field(min_length=1, max_length=512)
    thumbnail_key: Optional[str] = Field(default=None, max_length=512)
    image_type: str = Field(pattern=r"^(CCTV_VIEW|ENVIRONMENT)$")
    mime_type: str = Field(min_length=3, max_length=100)
    file_size: Optional[int] = Field(default=None, ge=0)
    width: Optional[int] = Field(default=None, ge=0)
    height: Optional[int] = Field(default=None, ge=0)


class ImageResponse(BaseModel):
    id: str
    cctv_record_id: str
    image_type: str
    object_key: str
    thumbnail_key: Optional[str] = None
    file_size: Optional[int] = None
    mime_type: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    created_at: datetime


class ImageUrlResponse(BaseModel):
    image_id: str
    url: str
    expires_in: int


class ImageUrlsResponse(BaseModel):
    """Presigned GET URLs for every image on a record, keyed by image id."""

    urls: dict[str, str]
    expires_in: int
