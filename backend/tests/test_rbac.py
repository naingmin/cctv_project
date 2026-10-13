"""RBAC security tests. These verify enforcement is server-side."""
from __future__ import annotations

from tests.conftest import auth

CCTV_PAYLOAD = {
    "cctv_id": "CCTV-YGN-000001",
    "latitude": 16.8409,
    "longitude": 96.1561,
    "region": "Yangon",
    "township": "Bahan",
    "street": "Main St",
    "status": "ACTIVE",
    "description": "Test camera",
}


def test_unauthenticated_cannot_list(client):
    assert client.get("/api/v1/cctvs").status_code == 401


def test_operator_can_create_owned_cctv(client, user_token):
    resp = client.post("/api/v1/cctvs", json=CCTV_PAYLOAD, headers=auth(user_token))
    assert resp.status_code == 201


def test_user_cannot_update_cctv(client, admin_token, user_token):
    created = client.post(
        "/api/v1/cctvs", json=CCTV_PAYLOAD, headers=auth(admin_token)
    ).json()["data"]
    resp = client.put(
        f"/api/v1/cctvs/{created['id']}",
        json={"description": "hacked"},
        headers=auth(user_token),
    )
    assert resp.status_code == 404


def test_user_cannot_delete_cctv(client, admin_token, user_token):
    created = client.post(
        "/api/v1/cctvs", json=CCTV_PAYLOAD, headers=auth(admin_token)
    ).json()["data"]
    resp = client.delete(
        f"/api/v1/cctvs/{created['id']}", headers=auth(user_token)
    )
    assert resp.status_code == 404


def test_operator_can_upload_only_to_owned_cctv(
    client, admin_token, user_token
):
    created = client.post(
        "/api/v1/cctvs", json=CCTV_PAYLOAD, headers=auth(admin_token)
    ).json()["data"]
    resp = client.post(
        "/api/v1/uploads/presign",
        json={
            "cctv_id": created["id"],
            "image_type": "CCTV_VIEW",
            "filename": "a.jpg",
            "content_type": "image/jpeg",
        },
        headers=auth(user_token),
    )
    assert resp.status_code == 404
    owned = client.post(
        "/api/v1/cctvs",
        json={**CCTV_PAYLOAD, "cctv_id": "CCTV-YGN-OWNED"},
        headers=auth(user_token),
    ).json()["data"]
    resp = client.post(
        "/api/v1/uploads/presign",
        json={
            "cctv_id": owned["id"],
            "image_type": "CCTV_VIEW",
            "filename": "a.jpg",
            "content_type": "image/jpeg",
        },
        headers=auth(user_token),
    )
    assert resp.status_code == 200
    resp = client.delete(
        f"/api/v1/cctvs/{owned['id']}/images/anything", headers=auth(user_token)
    )
    assert resp.status_code == 404


def test_user_cannot_manage_users(client, user_token):
    assert client.get("/api/v1/users", headers=auth(user_token)).status_code == 403
    assert (
        client.post(
            "/api/v1/users",
            json={
                "username": "x",
                "email": "x@example.com",
                "full_name": "X",
                "role": "USER",
                "password": "Xpass@1234",
            },
            headers=auth(user_token),
        ).status_code
        == 403
    )


def test_persisted_role_overrides_keycloak_role_claims():
    from bson import ObjectId

    from app.api.deps import CurrentUser
    from app.core.rbac import Role

    user = CurrentUser(
        {
            "_id": ObjectId(),
            "username": "operator",
            "email": "operator@example.com",
            "role": Role.OPERATOR.value,
        },
        keycloak_payload={"realm_access": {"roles": ["admin"]}},
    )
    assert user.role == Role.OPERATOR


def test_user_can_read_cctv(client, admin_token, user_token):
    client.post("/api/v1/cctvs", json=CCTV_PAYLOAD, headers=auth(admin_token))
    resp = client.get("/api/v1/cctvs", headers=auth(user_token))
    assert resp.status_code == 200
    assert resp.json()["data"]["pagination"]["total"] == 0
    own = client.post(
        "/api/v1/cctvs",
        json={**CCTV_PAYLOAD, "cctv_id": "CCTV-YGN-OWNED"},
        headers=auth(user_token),
    )
    assert own.status_code == 201
    assert client.get("/api/v1/cctvs", headers=auth(user_token)).json()["data"]["pagination"]["total"] == 1


def test_admin_crud_status_codes(client, admin_token):
    created = client.post(
        "/api/v1/cctvs", json=CCTV_PAYLOAD, headers=auth(admin_token)
    )
    assert created.status_code == 201

    cid = created.json()["data"]["id"]
    assert (
        client.put(
            f"/api/v1/cctvs/{cid}",
            json={"status": "INACTIVE"},
            headers=auth(admin_token),
        ).status_code
        == 200
    )
    assert (
        client.delete(f"/api/v1/cctvs/{cid}", headers=auth(admin_token)).status_code
        == 204
    )


def test_delete_actually_removes_record(client, admin_token):
    cid = client.post(
        "/api/v1/cctvs", json=CCTV_PAYLOAD, headers=auth(admin_token)
    ).json()["data"]["id"]

    assert client.delete(f"/api/v1/cctvs/{cid}", headers=auth(admin_token)).status_code == 204

    assert client.get(f"/api/v1/cctvs/{cid}", headers=auth(admin_token)).status_code == 404
    listed = client.get("/api/v1/cctvs", headers=auth(admin_token)).json()
    assert listed["data"]["pagination"]["total"] == 0
    # Deleting again is a clean 404, not a silent success.
    assert client.delete(f"/api/v1/cctvs/{cid}", headers=auth(admin_token)).status_code == 404
