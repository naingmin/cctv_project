"""Backend bootstrap: ensure indexes and seed the initial admin user.

Run once after MongoDB is available:

    python -m app.bootstrap
"""
from __future__ import annotations

from app.config import settings
from app.core.logging import configure_logging, get_logger
from app.db.mongo import connect, init_indexes
from app.services import storage_service, user_service

logger = get_logger(__name__)


def main() -> None:
    configure_logging()
    db = connect()
    init_indexes()

    user_service.ensure_default_admin(
        db,
        username=settings.DEFAULT_ADMIN_USERNAME,
        email=settings.DEFAULT_ADMIN_EMAIL,
        password=settings.DEFAULT_ADMIN_PASSWORD,
        full_name=settings.DEFAULT_ADMIN_FULL_NAME,
    )
    logger.info("Default admin ensured (only created if no users existed).")

    try:
        storage_service.ensure_bucket()
    except Exception as exc:
        logger.warning("Could not ensure object storage bucket yet: %s", exc)

    logger.info("Bootstrap complete.")


if __name__ == "__main__":
    main()
