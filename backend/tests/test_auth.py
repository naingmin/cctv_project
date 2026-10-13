"""Authentication and password tests."""
from __future__ import annotations

from datetime import datetime

from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)
from tests.conftest import ADMIN, USER, auth


def test_password_hash_and_verify():
    h = hash_password("Secret@123")
    assert h != "Secret@123"
    assert verify_password("Secret@123", h)
    assert not verify_password("wrong", h)


def test_login_success(client, admin_user):
    resp = client.post("/api/v1/auth/login", json=ADMIN)
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["access_token"]
    assert data["refresh_token"]
    assert data["token_type"] == "bearer"


def test_login_invalid_password(client, admin_user):
    resp = client.post(
        "/api/v1/auth/login",
        json={"username": ADMIN["username"], "password": "wrong"},
    )
    assert resp.status_code == 401
    assert resp.json()["success"] is False


def test_login_unknown_user_uses_same_message(client, admin_user):
    r1 = client.post(
        "/api/v1/auth/login", json={"username": "nobody", "password": "x"}
    )
    r2 = client.post(
        "/api/v1/auth/login",
        json={"username": ADMIN["username"], "password": "wrong"},
    )
    assert r1.status_code == r2.status_code == 401
    assert r1.json()["error"]["message"] == r2.json()["error"]["message"]


def test_me_requires_auth(client):
    assert client.get("/api/v1/auth/me").status_code == 401


def test_me_returns_role_and_permissions(client, admin_token):
    resp = client.get("/api/v1/auth/me", headers=auth(admin_token))
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["role"] == "OVERALL_ADMIN"
    assert "cctv.create" in data["permissions"]


def test_me_includes_user_timestamps(client, admin_token):
    """Regression: the Flutter UserModel requires created_at.

    /auth/me used to omit it, so UserModel.fromJson threw a TypeError on
    every login and surfaced as a generic "Login failed" message.
    """
    resp = client.get("/api/v1/auth/me", headers=auth(admin_token))
    assert resp.status_code == 200
    data = resp.json()["data"]
    for field in ("created_at", "updated_at"):
        assert data.get(field), "/auth/me must expose %s" % field
        datetime.fromisoformat(data[field].replace("Z", "+00:00"))
    # Must match the shape /users returns for the same user.
    listed = client.get("/api/v1/users", headers=auth(admin_token)).json()
    row = next(u for u in listed["data"]["items"] if u["id"] == data["id"])
    for field in ("created_at", "updated_at", "last_login_at"):
        assert row[field] == data[field]


def test_refresh_token_rotation(client, admin_user):
    login = client.post("/api/v1/auth/login", json=ADMIN).json()["data"]
    refresh_token = login["refresh_token"]

    r1 = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert r1.status_code == 200
    new_refresh = r1.json()["data"]["refresh_token"]
    assert new_refresh != refresh_token

    # Old refresh token must no longer work (rotation).
    r2 = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert r2.status_code == 401


def test_logout_revokes_refresh(client, admin_user):
    login = client.post("/api/v1/auth/login", json=ADMIN).json()["data"]
    token = login["access_token"]
    refresh_token = login["refresh_token"]

    assert (
        client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": refresh_token},
            headers=auth(token),
        ).status_code
        == 200
    )
    assert (
        client.post(
            "/api/v1/auth/refresh", json={"refresh_token": refresh_token}
        ).status_code
        == 401
    )


def test_change_password(client, admin_user):
    login = client.post("/api/v1/auth/login", json=ADMIN).json()["data"]
    token = login["access_token"]

    resp = client.post(
        "/api/v1/auth/change-password",
        json={"current_password": ADMIN["password"], "new_password": "NewPass@123"},
        headers=auth(token),
    )
    assert resp.status_code == 200

    # Old password no longer works, new one does.
    assert client.post("/api/v1/auth/login", json=ADMIN).status_code == 401
    assert (
        client.post(
            "/api/v1/auth/login",
            json={"username": ADMIN["username"], "password": "NewPass@123"},
        ).status_code
        == 200
    )


def test_weak_password_rejected(client, admin_user):
    login = client.post("/api/v1/auth/login", json=ADMIN).json()["data"]
    resp = client.post(
        "/api/v1/auth/change-password",
        json={"current_password": ADMIN["password"], "new_password": "short"},
        headers=auth(login["access_token"]),
    )
    assert resp.status_code == 422


def test_access_token_contains_claims():
    token, _ = create_access_token(subject="abc", role="ADMIN", token_version=3)
    payload = decode_access_token(token)
    assert payload["sub"] == "abc"
    assert payload["role"] == "ADMIN"
    assert payload["token_version"] == 3
