"""Refresh-token persistence and rotation."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from pymongo import ReturnDocument
from pymongo.database import Database

from app.core.logging import get_logger
from app.core.security import hash_refresh_token

logger = get_logger(__name__)


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


def _as_aware(value: datetime) -> datetime:
    """Normalize datetimes so comparisons are safe across backends.

    mongomock returns naive datetimes; MongoDB returns tz-aware ones.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def store_refresh_token(
    db: Database,
    *,
    user_id: str,
    raw_token: str,
    expires_at: datetime,
    user_agent: Optional[str] = None,
    ip_address: Optional[str] = None,
) -> None:
    db.refresh_tokens.insert_one(
        {
            "user_id": ObjectId(user_id),
            "token_hash": hash_refresh_token(raw_token),
            "expires_at": expires_at,
            "revoked": False,
            "created_at": _now(),
            "user_agent": (user_agent or "")[:512],
            "ip_address": ip_address,
        }
    )


def consume(db: Database, raw_token: str) -> Optional[str]:
    """Atomically revoke a valid refresh token and return its user id.

    Returns None for unknown, expired, or already-used tokens. Only one of
    any number of concurrent calls with the same token can succeed, because
    the revoke is conditional on ``revoked: False``.

    Presenting a token that was already rotated means it was copied (or the
    client replayed it); every session of that user is revoked so a stolen
    token cannot keep a parallel session alive.
    """
    token_hash = hash_refresh_token(raw_token)
    now = _now()
    claimed = db.refresh_tokens.find_one_and_update(
        {"token_hash": token_hash, "revoked": False},
        {"$set": {"revoked": True, "revoked_at": now}},
        return_document=ReturnDocument.BEFORE,
    )
    if claimed is None:
        reused = db.refresh_tokens.find_one(
            {"token_hash": token_hash, "revoked": True}, {"user_id": 1}
        )
        if reused is not None:
            logger.warning(
                "Refresh token reuse detected; revoking all sessions for user %s.",
                reused["user_id"],
            )
            revoke_all_for_user(db, str(reused["user_id"]))
        return None

    expires_at = claimed.get("expires_at")
    if expires_at and _as_aware(expires_at) < now:
        return None
    return str(claimed["user_id"])


def revoke_token(db: Database, *, user_id: str, raw_token: str) -> None:
    db.refresh_tokens.update_one(
        {
            "token_hash": hash_refresh_token(raw_token),
            "user_id": ObjectId(user_id),
            "revoked": False,
        },
        {"$set": {"revoked": True, "revoked_at": _now()}},
    )


def revoke_all_for_user(db: Database, user_id: str) -> None:
    db.refresh_tokens.update_many(
        {"user_id": ObjectId(user_id), "revoked": False},
        {"$set": {"revoked": True, "revoked_at": _now()}},
    )
