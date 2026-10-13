"""Authentication API routes."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status
from pymongo.database import Database

from app.api.deps import CurrentUser, get_current_user
from app.core.errors import UnauthorizedError, success
from app.core.rbac import permissions_for_role
from app.core.rate_limit import enforce_login_rate_limit, enforce_sensitive_rate_limit
from app.core.security import (
    create_access_token,
    create_refresh_token,
    validate_password_strength,
    verify_password,
)
from app.db.mongo import get_db
from app.schemas.auth import (
    ChangePasswordRequest,
    LoginRequest,
    MeResponse,
    RefreshRequest,
)
from app.services import audit_service, token_service, user_service

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/login", status_code=status.HTTP_200_OK)
def login(
    payload: LoginRequest,
    request: Request,
    db: Database = Depends(get_db),
):
    enforce_login_rate_limit(request)

    user = user_service.get_by_username_or_email(db, payload.username)
    if not user or not verify_password(payload.password, user.get("password_hash", "")):
        audit_service.record(
            db,
            action=audit_service.LOGIN_FAILED,
            ip_address=request.client.host if request.client else None,
            metadata={"identifier": payload.username},
        )
        # Do not reveal whether the username exists.
        raise UnauthorizedError("Invalid username or password.")

    if not user.get("is_active", True):
        raise UnauthorizedError("Your account has been disabled.")

    user_id = str(user["_id"])
    role = user.get("role", "USER")
    token_version = user.get("token_version", 1)

    access_token, expires_in = create_access_token(
        subject=user_id, role=role, token_version=token_version
    )
    refresh_token, refresh_expires = create_refresh_token()
    token_service.store_refresh_token(
        db,
        user_id=user_id,
        raw_token=refresh_token,
        expires_at=refresh_expires,
        user_agent=request.headers.get("user-agent"),
        ip_address=request.client.host if request.client else None,
    )
    user_service.touch_last_login(db, user_id)
    audit_service.record(
        db,
        action=audit_service.LOGIN_SUCCESS,
        user_id=user_id,
        ip_address=request.client.host if request.client else None,
    )

    return success(
        {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "expires_in": expires_in,
        },
        message="Login successful.",
    )


@router.post("/refresh", status_code=status.HTTP_200_OK)
def refresh(
    payload: RefreshRequest,
    request: Request,
    db: Database = Depends(get_db),
):
    enforce_sensitive_rate_limit(request)

    # One indexed lookup + atomic revoke: the old token is spent whether or
    # not the rest of this request succeeds.
    user_id = token_service.consume(db, payload.refresh_token)
    user_doc = user_service.get_by_id(db, user_id) if user_id else None
    if not user_doc:
        raise UnauthorizedError("Invalid or expired refresh token.")
    if not user_doc.get("is_active", True):
        raise UnauthorizedError("Your account has been disabled.")

    new_raw, new_expires = create_refresh_token()
    token_service.store_refresh_token(
        db,
        user_id=user_id,
        raw_token=new_raw,
        expires_at=new_expires,
        user_agent=request.headers.get("user-agent"),
        ip_address=request.client.host if request.client else None,
    )

    access_token, expires_in = create_access_token(
        subject=user_id,
        role=user_doc.get("role", "USER"),
        token_version=user_doc.get("token_version", 1),
    )
    return success(
        {
            "access_token": access_token,
            "refresh_token": new_raw,
            "token_type": "bearer",
            "expires_in": expires_in,
        },
        message="Token refreshed.",
    )


@router.post("/logout", status_code=status.HTTP_200_OK)
def logout(
    payload: RefreshRequest,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    token_service.revoke_token(db, user_id=user.id, raw_token=payload.refresh_token)
    audit_service.record(
        db,
        action=audit_service.LOGOUT,
        user_id=user.id,
        ip_address=request.client.host if request.client else None,
    )
    return success(message="Logged out.")


@router.get("/me", response_model=None, status_code=status.HTTP_200_OK)
def me(user: CurrentUser = Depends(get_current_user)):
    last_login = user.last_login_at
    if isinstance(last_login, tuple):
        last_login = last_login[0] if last_login else None
    me_response = MeResponse(
        id=user.id,
        username=user.username,
        email=user.email,
        full_name=user.full_name,
        role=user.role.value,
        is_active=user.is_active,
        region_id=user.region_id,
        sub_region_id=user.sub_region_id,
        region=user.region,
        township=user.township,
        permissions=sorted(p.value for p in permissions_for_role(user.role)),
        created_at=user.created_at,
        updated_at=user.updated_at,
        last_login_at=last_login,
    )
    return success(me_response.model_dump(), message="OK")


@router.post("/change-password", status_code=status.HTTP_200_OK)
def change_password(
    payload: ChangePasswordRequest,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    enforce_sensitive_rate_limit(request)

    doc = user_service.get_by_id(db, user.id)
    if not doc or not verify_password(payload.current_password, doc.get("password_hash", "")):
        raise UnauthorizedError("Current password is incorrect.")

    try:
        validate_password_strength(payload.new_password)
    except ValueError as exc:
        from app.core.errors import ValidationError

        raise ValidationError(str(exc))

    user_service.set_password(db, user.id, payload.new_password)
    # Invalidate all other sessions.
    token_service.revoke_all_for_user(db, user.id)
    audit_service.record(
        db,
        action=audit_service.PASSWORD_CHANGED,
        user_id=user.id,
        ip_address=request.client.host if request.client else None,
    )
    return success(message="Password changed. Please log in again.")
