"""User schemas."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field

from app.core.rbac import Role


class UserBase(BaseModel):
    username: str = Field(min_length=3, max_length=64, pattern=r"^[A-Za-z0-9_.-]+$")
    email: EmailStr
    full_name: str = Field(min_length=1, max_length=200)
    # Role is required; default is OPERATOR for new users when Keycloak is not active.
    # When using legacy auth, this would be USER, but we've moved to the hierarchical model.
    role: Role = Role.OPERATOR
    is_active: bool = True
    # Keycloak integration
    keycloak_user_id: Optional[str] = Field(default=None, max_length=128)
    # Geographic scope
    region_id: Optional[str] = Field(default=None, max_length=120)
    sub_region_id: Optional[str] = Field(default=None, max_length=120)
    region: Optional[str] = Field(default=None, max_length=120)
    township: Optional[str] = Field(default=None, max_length=120)


class UserCreate(UserBase):
    # Password is handled by Keycloak; this field is kept for backward compatibility
    # but should not be used when Keycloak is the authoritative identity provider.
    password: str = Field(min_length=8, max_length=256, default="")


class UserUpdate(BaseModel):
    full_name: Optional[str] = Field(default=None, min_length=1, max_length=200)
    role: Optional[Role] = None
    is_active: Optional[bool] = None
    region: Optional[str] = Field(default=None, max_length=120)
    township: Optional[str] = Field(default=None, max_length=120)
    region_id: Optional[str] = Field(default=None, max_length=120)
    sub_region_id: Optional[str] = Field(default=None, max_length=120)


class UserResponse(BaseModel):
    id: str
    username: str
    email: EmailStr
    full_name: str
    role: Role
    is_active: bool
    keycloak_user_id: Optional[str] = None
    region: Optional[str] = None
    township: Optional[str] = None
    region_id: Optional[str] = None
    sub_region_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    last_login_at: Optional[datetime] = None
