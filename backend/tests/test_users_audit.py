"""User management and audit log tests."""
from __future__ import annotations

from tests.conftest import auth


def _new_user(**overrides):
    base = {
        "username": "operator",
        "email": "operator@example.com",
        "full_name": "Operator",
        "role": "USER",
        "is_active": True,
        "password": "Operator@123",
    }
    base.update(overrides)
    return base


def test_admin_can_create_and_list_users(client, admin_token):
    created = client.post(
        "/api/v1/users", json=_new_user(), headers=auth(admin_token)
    )
    assert created.status_code == 201

    listing = client.get("/api/v1/users", headers=auth(admin_token)).json()["data"]
    usernames = [u["username"] for u in listing["items"]]
    assert "operator" in usernames


def test_duplicate_username_conflict(client, admin_token):
    client.post("/api/v1/users", json=_new_user(), headers=auth(admin_token))
    dup = client.post("/api/v1/users", json=_new_user(), headers=auth(admin_token))
    assert dup.status_code == 409


def test_disable_user(client, admin_token):
    created = client.post(
        "/api/v1/users", json=_new_user(), headers=auth(admin_token)
    ).json()["data"]

    resp = client.put(
        f"/api/v1/users/{created['id']}",
        json={"is_active": False},
        headers=auth(admin_token),
    )
    assert resp.status_code == 200
    assert resp.json()["data"]["is_active"] is False

    # Disabled user cannot log in.
    assert (
        client.post(
            "/api/v1/auth/login",
            json={"username": "operator", "password": "Operator@123"},
        ).status_code
        == 401
    )


def test_cannot_demote_last_admin(client, admin_user, admin_token):
    resp = client.put(
        f"/api/v1/users/{admin_user['_id']}",
        json={"role": "USER"},
        headers=auth(admin_token),
    )
    assert resp.status_code == 422


def test_cannot_delete_self(client, admin_user, admin_token):
    resp = client.delete(
        f"/api/v1/users/{admin_user['_id']}", headers=auth(admin_token)
    )
    assert resp.status_code == 422


def test_cannot_change_own_role(client, admin_user, admin_token):
    resp = client.put(
        f"/api/v1/users/{admin_user['_id']}",
        json={"role": "USER"},
        headers=auth(admin_token),
    )
    # Either "cannot change own role" or last-admin protection; both 422.
    assert resp.status_code == 422


def test_audit_logs_recorded(client, admin_token):
    client.post(
        "/api/v1/cctvs",
        json={
            "cctv_id": "CCTV-YGN-000777",
            "latitude": 16.84,
            "longitude": 96.15,
            "status": "ACTIVE",
        },
        headers=auth(admin_token),
    )
    logs = client.get("/api/v1/audit-logs", headers=auth(admin_token)).json()["data"]
    actions = [entry["action"] for entry in logs["items"]]
    assert "LOGIN_SUCCESS" in actions
    assert "CREATE_CCTV" in actions
    created = next(entry for entry in logs["items"] if entry["action"] == "CREATE_CCTV")
    assert created["username"] == "admin"
    assert created["user_role"] == "System Admin"
    assert created["cctv_id"] == "CCTV-YGN-000777"
    assert created["cctv_name"] == "CCTV-YGN-000777"
    assert created["region_id"] is None
    assert created["sub_region_id"] is None
    assert created["ip_address"]
    assert client.get(
        f"/api/v1/cctvs/{created['resource_id']}", headers=auth(admin_token)
    ).status_code == 200
    viewed = client.get(
        "/api/v1/audit-logs?action=VIEW_CCTV", headers=auth(admin_token)
    ).json()["data"]["items"]
    assert any(item["cctv_id"] == "CCTV-YGN-000777" for item in viewed)
