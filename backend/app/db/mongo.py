"""MongoDB connection management and index initialization."""
from __future__ import annotations

from typing import Optional

from pymongo import ASCENDING, DESCENDING, MongoClient
from pymongo.database import Database

from app.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_client: Optional[MongoClient] = None
_db: Optional[Database] = None


def connect() -> Database:
    """Create (or reuse) the MongoDB client and database handle."""
    global _client, _db
    if _db is not None:
        return _db
    _client = MongoClient(
        settings.MONGODB_URI,
        uuidRepresentation="standard",
        serverSelectionTimeoutMS=5000,
    )
    _db = _client[settings.MONGODB_DATABASE]
    return _db


def get_db() -> Database:
    if _db is None:
        return connect()
    return _db


def close() -> None:
    global _client, _db
    if _client is not None:
        _client.close()
    _client = None
    _db = None


def _replace_index(collection, name: str) -> None:
    """Drop an index superseded by a newer definition, if it exists."""
    try:
        if name in collection.index_information():
            collection.drop_index(name)
    except Exception as exc:  # pragma: no cover - best effort on old servers
        logger.warning("Could not drop index %s: %s", name, exc)


def init_indexes() -> None:
    """Create the indexes required by the application's query patterns."""
    db = get_db()

    # users
    db.users.create_index("username", unique=True, name="uniq_username")
    db.users.create_index("email", unique=True, name="uniq_email")
    db.users.create_index("role", name="ix_role")
    db.users.create_index("is_active", name="ix_is_active")
    db.users.create_index(
        [("region_id", ASCENDING), ("sub_region_id", ASCENDING), ("role", ASCENDING)],
        name="ix_user_scope_ids",
    )
    db.users.create_index(
        [("region", ASCENDING), ("township", ASCENDING), ("role", ASCENDING)],
        name="ix_user_scope_names",
    )

    # cctvs
    db.cctvs.create_index("cctv_id", unique=True, name="uniq_cctv_id")
    db.cctvs.create_index([("location", "2dsphere")], name="geo_location")
    db.cctvs.create_index("status", name="ix_status")
    db.cctvs.create_index("tags", name="ix_tags")
    db.cctvs.create_index("region", name="ix_region")
    db.cctvs.create_index("township", name="ix_township")
    db.cctvs.create_index("region_id", name="ix_region_id")
    db.cctvs.create_index("sub_region_id", name="ix_sub_region_id")
    db.cctvs.create_index([("created_at", DESCENDING)], name="ix_created_at")
    db.cctvs.create_index("created_by", name="ix_created_by")
    # Scoped listings filter by region/township and sort by newest first.
    db.cctvs.create_index(
        [("region", ASCENDING), ("township", ASCENDING), ("created_at", DESCENDING)],
        name="ix_scope_created_at",
    )

    # refresh_tokens
    # Refresh tokens are looked up by their SHA-256 hash. Older documents
    # hold salted Argon2 hashes under the same field; those are simply never
    # matched again (their users sign in once more) and expire via the TTL.
    _replace_index(db.refresh_tokens, "ix_token_hash")
    db.refresh_tokens.create_index(
        "token_hash", unique=True, name="uniq_token_hash"
    )
    db.refresh_tokens.create_index(
        [("user_id", ASCENDING), ("revoked", ASCENDING)], name="ix_rt_user_revoked"
    )
    _replace_index(db.refresh_tokens, "ix_rt_user_id")
    db.refresh_tokens.create_index(
        [("expires_at", ASCENDING)], name="ix_rt_expires", expireAfterSeconds=0
    )

    # audit_logs
    db.audit_logs.create_index("user_id", name="ix_audit_user")
    db.audit_logs.create_index("action", name="ix_audit_action")
    db.audit_logs.create_index("resource_id", name="ix_audit_resource")
    db.audit_logs.create_index("cctv_created_by", name="ix_audit_cctv_owner")
    db.audit_logs.create_index(
        [("region_id", ASCENDING), ("sub_region_id", ASCENDING)],
        name="ix_audit_geo_scope",
    )
    db.audit_logs.create_index(
        [("region", ASCENDING), ("sub_region", ASCENDING)],
        name="ix_audit_geo_names",
    )
    db.audit_logs.create_index(
        [("timestamp", DESCENDING)], name="ix_audit_timestamp"
    )

    logger.info("MongoDB indexes ensured.")
