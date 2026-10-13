"""Authentication schemas."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field


class LoginRequest(BaseModel):
    # Accept either username or email in a single field.
    username: str = Field(min_length=1, max_length=320)
    password: str = Field(min_length=1, max_length=256)


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=10, max_length=128)


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=8, max_length=256)


class MeResponse(BaseModel):
    id: str
    username: str
    email: EmailStr
    full_name: str
    role: str
    is_active: bool
    region_id: Optional[str] = None
    sub_region_id: Optional[str] = None
    region: Optional[str] = None
    township: Optional[str] = None
    permissions: list[str]
    # Kept in step with UserResponse: clients parse /auth/me into the same
    # user model used for /users, and that model requires created_at.
    created_at: datetime
    updated_at: datetime
    last_login_at: Optional[datetime] = None
