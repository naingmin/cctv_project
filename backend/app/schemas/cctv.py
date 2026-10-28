"""CCTV schemas."""
from __future__ import annotations

import ipaddress
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator, model_validator

from app.core.rbac import Permission  # noqa: F401  (re-exported for docs)

CCTV_TAGS = {"ALPRS", "FRS", "CPCS", "ARDS"}


def _validate_ip_address(value: Optional[str]) -> Optional[str]:
    if value is None or not value.strip():
        return None
    try:
        return str(ipaddress.ip_address(value.strip()))
    except ValueError as exc:
        raise ValueError("IP address must be a valid IPv4 or IPv6 address.") from exc


class ImageMeta(BaseModel):
    id: str
    image_type: str
    object_key: str
    thumbnail_key: Optional[str] = None
    file_size: Optional[int] = None
    mime_type: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    created_at: datetime


def _validate_latitude(v: float) -> float:
    if v < -90 or v > 90:
        raise ValueError("Latitude must be between -90 and 90.")
    return v


def _validate_longitude(v: float) -> float:
    if v < -180 or v > 180:
        raise ValueError("Longitude must be between -180 and 180.")
    return v


class CctvBase(BaseModel):
    cctv_id: str = Field(min_length=3, max_length=64)
    latitude: float
    longitude: float
    region_id: Optional[str] = Field(default=None, max_length=120)
    sub_region_id: Optional[str] = Field(default=None, max_length=120)
    region: Optional[str] = Field(default=None, max_length=120)
    township: Optional[str] = Field(default=None, max_length=120)
    street: Optional[str] = Field(default=None, max_length=200)
    direction: Optional[str] = Field(default=None, pattern=r"^(N|NE|E|SE|S|SW|W|NW)$")
    description: Optional[str] = Field(default=None, max_length=2000)
    ip_address: Optional[str] = Field(default=None, max_length=45)
    rtsp_port: Optional[int] = Field(
        default=554, ge=1, le=65535, description="RTSP Port number"
    )
    username: Optional[str] = Field(default=None, max_length=256)
    password: Optional[str] = Field(default=None, max_length=1024)
    tags: List[str] = Field(default_factory=list, max_length=4)
    status: str = Field(default="ACTIVE", pattern=r"^(ACTIVE|INACTIVE|MAINTENANCE)$")
    type: Optional[str] = Field(default=None, pattern=r"^(Dome|Bullet|PTZ)$")

    @field_validator("ip_address")
    @classmethod
    def _ip_address(cls, value: Optional[str]) -> Optional[str]:
        return _validate_ip_address(value)

    @field_validator("tags")
    @classmethod
    def _tags(cls, value: List[str]) -> List[str]:
        if any(tag not in CCTV_TAGS for tag in value):
            raise ValueError(f"Tags must be selected from {sorted(CCTV_TAGS)}.")
        if len(value) != len(set(value)):
            raise ValueError("Tags cannot contain duplicates.")
        return value

    @field_validator("latitude")
    @classmethod
    def _lat(cls, v: float) -> float:
        return _validate_latitude(v)

    @field_validator("longitude")
    @classmethod
    def _lng(cls, v: float) -> float:
        return _validate_longitude(v)

    @field_validator("cctv_id")
    @classmethod
    def _normalize_cctv_id(cls, v: str) -> str:
        v = v.strip().upper()
        if not v:
            raise ValueError("CCTV ID is required.")
        return v


class CctvCreate(CctvBase):
    pass


class CctvUpdate(BaseModel):
    cctv_id: Optional[str] = Field(default=None, min_length=3, max_length=64)
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    region_id: Optional[str] = Field(default=None, max_length=120)
    sub_region_id: Optional[str] = Field(default=None, max_length=120)
    region: Optional[str] = Field(default=None, max_length=120)
    township: Optional[str] = Field(default=None, max_length=120)
    street: Optional[str] = Field(default=None, max_length=200)
    direction: Optional[str] = Field(default=None, pattern=r"^(N|NE|E|SE|S|SW|W|NW)$")
    description: Optional[str] = Field(default=None, max_length=2000)
    ip_address: Optional[str] = Field(default=None, max_length=45)
    rtsp_port: Optional[int] = Field(
        default=None, ge=1, le=65535, description="RTSP Port number"
    )
    username: Optional[str] = Field(default=None, max_length=256)
    password: Optional[str] = Field(default=None, max_length=1024)
    tags: Optional[List[str]] = Field(default=None, max_length=4)
    status: Optional[str] = Field(default=None, pattern=r"^(ACTIVE|INACTIVE|MAINTENANCE)$")
    type: Optional[str] = Field(default=None, pattern=r"^(Dome|Bullet|PTZ)$")

    @field_validator("ip_address")
    @classmethod
    def _ip_address(cls, value: Optional[str]) -> Optional[str]:
        return _validate_ip_address(value)

    @field_validator("tags")
    @classmethod
    def _tags(cls, value: Optional[List[str]]) -> Optional[List[str]]:
        if value is None:
            return None
        if any(tag not in CCTV_TAGS for tag in value):
            raise ValueError(f"Tags must be selected from {sorted(CCTV_TAGS)}.")
        if len(value) != len(set(value)):
            raise ValueError("Tags cannot contain duplicates.")
        return value

    @field_validator("latitude")
    @classmethod
    def _lat(cls, v):
        return None if v is None else _validate_latitude(v)

    @field_validator("longitude")
    @classmethod
    def _lng(cls, v):
        return None if v is None else _validate_longitude(v)

    @field_validator("cctv_id")
    @classmethod
    def _normalize_cctv_id(cls, v):
        return None if v is None else v.strip().upper()

    @model_validator(mode="after")
    def _coords_together(self):
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("latitude and longitude must be provided together.")
        return self


class CctvResponse(BaseModel):
    id: str
    cctv_id: str
    latitude: float
    longitude: float
    region_id: Optional[str] = None
    sub_region_id: Optional[str] = None
    region: Optional[str] = None
    township: Optional[str] = None
    street: Optional[str] = None
    direction: Optional[str] = None
    ip_address: Optional[str] = None
    rtsp_port: Optional[int] = Field(
        default=554, description="RTSP Port number"
    )
    username: Optional[str] = None
    password: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    status: str
    last_checked: Optional[datetime] = None
    description: Optional[str] = None
    images: List[ImageMeta] = []
    # Presigned GET URL for the primary view image, resolved per response.
    # Never persisted - clients cannot use a stored copy because it expires.
    view_image_url: Optional[str] = None
    created_by: Optional[str] = None
    updated_by: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class CctvMarker(BaseModel):
    """Lightweight payload for map rendering."""

    id: str
    cctv_id: str
    latitude: float
    longitude: float
    direction: Optional[str] = None
    status: str
    thumbnail_url: Optional[str] = None


class NearbyQuery(BaseModel):
    latitude: float
    longitude: float
    radius_meters: float = Field(gt=0, le=50_000)
