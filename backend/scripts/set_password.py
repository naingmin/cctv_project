"""Set a user's password from the command line.

Usage (from the backend/ directory):

    python -m scripts.set_password admin

The password is prompted for and never echoed, logged, or passed on the
command line (where it would end up in shell history). Existing sessions for
the user are revoked.
"""
from __future__ import annotations

import getpass
import sys

from app.core.security import validate_password_strength
from app.db.mongo import connect
from app.services import audit_service, token_service, user_service


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python -m scripts.set_password <username-or-email>")
        return 2

    db = connect()
    user = user_service.get_by_username_or_email(db, sys.argv[1])
    if not user:
        print("User not found.")
        return 1

    password = getpass.getpass("New password: ")
    try:
        validate_password_strength(password)
    except ValueError as exc:
        print(exc)
        return 1
    if getpass.getpass("Repeat password: ") != password:
        print("Passwords do not match.")
        return 1

    user_id = str(user["_id"])
    user_service.set_password(db, user_id, password)
    token_service.revoke_all_for_user(db, user_id)
    audit_service.record(
        db,
        action=audit_service.PASSWORD_CHANGED,
        user_id=user_id,
        ip_address=None,
    )
    print(f"Password updated for '{user['username']}'. Existing sessions revoked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
