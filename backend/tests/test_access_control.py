"""Geographic scoping, user-role rules and refresh-token hardening."""
from __future__ import annotations

import pytest

from app.core.errors import ValidationError
from app.core.rbac import Role
from app.schemas.user import UserCreate, UserUpdate
from app.services import user_service
from tests.conftest import auth

PASSWORD = "Scoped@12345"


def _cctv(cctv_id, region, township, lat):
    return {
        "cctv_id": cctv_id,
        "latitude": lat,
        "longitude": 96.15,
        "region": region,
        "township": township,
        "status": "ACTIVE",
    }


@pytest.fixture()
def records(client, admin_token):
    """One CCTV in Yangon/Bahan, one in Yangon/Kamayut, one in Mandalay."""
    ids = {}
    for key, payload in {
        "bahan": _cctv("CCTV-YGN-1", "Yangon", "Bahan", 16.80),
        "kamayut": _cctv("CCTV-YGN-2", "Yangon", "Kamayut", 16.81),
        "mandalay": _cctv("CCTV-MDY-1", "Mandalay", "Chanayethazan", 21.97),
    }.items():
        resp = client.post("/api/v1/cctvs", json=payload, headers=auth(admin_token))
        assert resp.status_code == 201, resp.text
        ids[key] = resp.json()["data"]["id"]
    return ids


def _login_as(
    client, db, username, role, region=None, township=None,
    region_id=None, sub_region_id=None,
):
    # Role and area are written directly so tests can also build
    # *misconfigured* accounts (e.g. a regional admin without a region) that
    # the API itself would refuse to create.
    doc = user_service.create_user(
        db,
        UserCreate(
            username=username,
            email=f"{username}@example.com",
            full_name=username,
            role=Role.OPERATOR,
            password=PASSWORD,
        ),
    )
    db.users.update_one(
        {"_id": doc["_id"]},
        {
            "$set": {
                "role": role.value,
                "region": region,
                "township": township,
                "region_id": region_id,
                "sub_region_id": sub_region_id,
            }
        },
    )
    resp = client.post(
        "/api/v1/auth/login", json={"username": username, "password": PASSWORD}
    )
    assert resp.status_code == 200, resp.text
    return auth(resp.json()["data"]["access_token"])


def _list_ids(client, headers, query=""):
    resp = client.get(f"/api/v1/cctvs{query}", headers=headers)
    assert resp.status_code == 200, resp.text
    return {item["id"] for item in resp.json()["data"]["items"]}


# --- Operator: CCTV records created by this account ------------------------


def test_operator_reads_only_owned_records(client, user_token, records):
    headers = auth(user_token)
    assert _list_ids(client, headers) == set()
    for record_id in records.values():
        assert client.get(f"/api/v1/cctvs/{record_id}", headers=headers).status_code == 404


def test_operator_can_write_only_owned_records(client, user_token, records):
    headers = auth(user_token)
    assert client.put(
        f"/api/v1/cctvs/{records['bahan']}", json={"status": "INACTIVE"}, headers=headers
    ).status_code == 404
    assert client.delete(
        f"/api/v1/cctvs/{records['bahan']}", headers=headers
    ).status_code == 404
    created = client.post(
        "/api/v1/cctvs", json=_cctv("CCTV-X", "Yangon", "Bahan", 16.9), headers=headers
    )
    assert created.status_code == 201, created.text
    camera_id = created.json()["data"]["id"]
    assert client.put(
        f"/api/v1/cctvs/{camera_id}", json={"status": "INACTIVE"}, headers=headers
    ).status_code == 200
    assert client.delete(f"/api/v1/cctvs/{camera_id}", headers=headers).status_code == 204


# --- Regional admin: own region only ----------------------------------------


def test_regional_admin_sees_only_own_region(client, db, records):
    headers = _login_as(client, db, "ygn_admin", Role.REGIONAL_ADMIN, region="Yangon")
    assert _list_ids(client, headers) == {records["bahan"], records["kamayut"]}
    assert client.get(
        f"/api/v1/cctvs/{records['mandalay']}", headers=headers
    ).status_code == 404
    # A client filter can narrow the view but never widen it.
    assert _list_ids(client, headers, "?region=Mandalay") == set()
    assert _list_ids(client, headers, "?search=MDY") == set()


def test_regional_admin_stats_are_scoped(client, db, records):
    headers = _login_as(client, db, "ygn_admin", Role.REGIONAL_ADMIN, region="Yangon")
    stats = client.get("/api/v1/cctvs/stats", headers=headers).json()["data"]
    assert stats["total_cctv"] == 2
    assert stats["added_today"] == 2
    # User counts are reserved for user administrators.
    assert stats["total_users"] == 0


def test_regional_admin_writes_only_inside_region(client, db, records):
    headers = _login_as(client, db, "ygn_admin", Role.REGIONAL_ADMIN, region="Yangon")

    # Create inside their region: allowed. Elsewhere or unscoped: refused.
    assert client.post(
        "/api/v1/cctvs", json=_cctv("CCTV-YGN-9", "Yangon", "Bahan", 16.9), headers=headers
    ).status_code == 201
    assert client.post(
        "/api/v1/cctvs", json=_cctv("CCTV-MDY-9", "Mandalay", None, 21.9), headers=headers
    ).status_code == 403
    assert client.post(
        "/api/v1/cctvs", json=_cctv("CCTV-NONE", None, None, 17.0), headers=headers
    ).status_code == 403

    # Update inside: allowed. Moving out of the region or clearing it: refused.
    url = f"/api/v1/cctvs/{records['bahan']}"
    assert client.put(url, json={"status": "MAINTENANCE"}, headers=headers).status_code == 200
    assert client.put(url, json={"region": "Mandalay"}, headers=headers).status_code == 403
    assert client.put(url, json={"region": None}, headers=headers).status_code == 403

    # Records in other regions cannot be touched at all.
    assert client.put(
        f"/api/v1/cctvs/{records['mandalay']}", json={"status": "INACTIVE"}, headers=headers
    ).status_code == 404


def test_regional_admin_without_region_is_denied(client, db, records):
    headers = _login_as(client, db, "lost_admin", Role.REGIONAL_ADMIN, region=None)
    # Used to mean "global access"; now it means no access.
    assert client.get("/api/v1/cctvs", headers=headers).status_code == 403
    assert client.get(
        f"/api/v1/cctvs/{records['bahan']}", headers=headers
    ).status_code == 403
    assert client.get("/api/v1/cctvs/stats", headers=headers).status_code == 403


# --- Supervisor: region + township, read-only -------------------------------


def test_supervisor_sees_only_own_township(client, db, records):
    headers = _login_as(
        client, db, "bahan_sup", Role.SUPERVISOR, region="Yangon", township="Bahan"
    )
    assert _list_ids(client, headers) == {records["bahan"]}
    assert client.get(
        f"/api/v1/cctvs/{records['kamayut']}", headers=headers
    ).status_code == 404
    # Search combined with scope (search used to be dropped for supervisors).
    assert _list_ids(client, headers, "?search=YGN") == {records["bahan"]}
    assert _list_ids(client, headers, "?search=nomatch") == set()
    assert client.put(
        f"/api/v1/cctvs/{records['bahan']}", json={"status": "INACTIVE"}, headers=headers
    ).status_code == 200


def test_supervisor_without_township_is_denied(client, db, records):
    headers = _login_as(client, db, "half_sup", Role.SUPERVISOR, region="Yangon")
    assert client.get("/api/v1/cctvs", headers=headers).status_code == 403


# --- Area suggestions ----------------------------------------------------------


def test_areas_lists_regions_and_townships(client, admin_token, records):
    resp = client.get("/api/v1/cctvs/areas", headers=auth(admin_token))
    assert resp.status_code == 200
    assert resp.json()["data"]["regions"] == {
        "Mandalay": ["Chanayethazan"],
        "Yangon": ["Bahan", "Kamayut"],
    }


def test_areas_are_scoped(client, db, records):
    headers = _login_as(client, db, "ygn_admin", Role.REGIONAL_ADMIN, region="Yangon")
    regions = client.get("/api/v1/cctvs/areas", headers=headers).json()["data"]["regions"]
    assert list(regions) == ["Yangon"]


def test_regional_and_supervisor_user_management_is_scoped(client, db, admin_token):
    admin_headers = auth(admin_token)
    region_user = client.post(
        "/api/v1/users",
        json=_user_payload(
            username="regional",
            email="regional@example.com",
            role="REGIONAL_ADMIN",
            region="Yangon",
        ),
        headers=admin_headers,
    )
    assert region_user.status_code == 201, region_user.text
    regional_headers = _login_as(
        client, db, "manager_ygn", Role.REGIONAL_ADMIN, region="Yangon"
    )
    # A regional manager may manage supervisors/operators in-region but cannot
    # elevate a child user to another administrator role.
    supervisor = client.post(
        "/api/v1/users",
        json=_user_payload(
            username="bahan_supervisor",
            email="bahan_supervisor@example.com",
            role="SUPERVISOR",
            region="Yangon",
            township="Bahan",
        ),
        headers=regional_headers,
    )
    assert supervisor.status_code == 201, supervisor.text
    assert client.post(
        "/api/v1/users",
        json=_user_payload(
            username="outside_operator",
            email="outside_operator@example.com",
            role="OPERATOR",
            region="Mandalay",
        ),
        headers=regional_headers,
    ).status_code == 403
    assert client.post(
        "/api/v1/users",
        json=_user_payload(
            username="escalated_admin",
            email="escalated_admin@example.com",
            role="REGIONAL_ADMIN",
            region="Yangon",
        ),
        headers=regional_headers,
    ).status_code == 403

    supervisor_headers = _login_as(
        client, db, "manager_bahan", Role.SUPERVISOR, region="Yangon", township="Bahan"
    )
    operator = client.post(
        "/api/v1/users",
        json=_user_payload(
            username="bahan_operator",
            email="bahan_operator@example.com",
            role="OPERATOR",
            region="Yangon",
            township="Bahan",
        ),
        headers=supervisor_headers,
    )
    assert operator.status_code == 201, operator.text
    assert client.post(
        "/api/v1/users",
        json=_user_payload(
            username="kamayut_operator",
            email="kamayut_operator@example.com",
            role="OPERATOR",
            region="Yangon",
            township="Kamayut",
        ),
        headers=supervisor_headers,
    ).status_code == 403
    assert client.get(
        f"/api/v1/users/{operator.json()['data']['id']}",
        headers=regional_headers,
    ).status_code == 200


def test_operator_cctv_id_scope_and_audit_logs(client, db, admin_token):
    headers = _login_as(
        client,
        db,
        "id_region_admin",
        Role.REGIONAL_ADMIN,
        region="Yangon",
        region_id="region-ygn",
    )
    own = client.post(
        "/api/v1/cctvs",
        json=_cctv("CCTV-ID-1", "Yangon", "Bahan", 16.8)
        | {"region_id": "region-ygn"},
        headers=headers,
    )
    assert own.status_code == 201, own.text
    other = client.post(
        "/api/v1/cctvs",
        json=_cctv("CCTV-ID-2", "Yangon", "Bahan", 16.81)
        | {"region_id": "region-other"},
        headers=auth(admin_token),
    )
    assert other.status_code == 201
    assert _list_ids(client, headers) == {own.json()["data"]["id"]}
    assert client.get(
        f"/api/v1/cctvs/{other.json()['data']['id']}", headers=headers
    ).status_code == 404
    audit = client.get("/api/v1/audit-logs", headers=headers)
    assert audit.status_code == 200
    assert {
        item["cctv_id"] for item in audit.json()["data"]["items"] if item["cctv_id"]
    } == {"CCTV-ID-1"}


# --- Search safety -----------------------------------------------------------


@pytest.mark.parametrize("text", ["(", "[", ".*", "a+b", "\\"])
def test_search_treats_regex_characters_literally(client, admin_token, records, text):
    resp = client.get(f"/api/v1/cctvs?search={text}", headers=auth(admin_token))
    assert resp.status_code == 200
    assert resp.json()["data"]["pagination"]["total"] == 0


# --- User management -----------------------------------------------------------


def _user_payload(**overrides):
    base = {
        "username": "newuser",
        "email": "newuser@example.com",
        "full_name": "New User",
        "role": "USER",
        "password": "NewUser@123",
    }
    base.update(overrides)
    return base


def test_scoped_roles_require_an_area(client, admin_token):
    headers = auth(admin_token)
    assert client.post(
        "/api/v1/users", json=_user_payload(role="REGIONAL_ADMIN"), headers=headers
    ).status_code == 422
    assert client.post(
        "/api/v1/users",
        json=_user_payload(role="SUPERVISOR", region="Yangon"),
        headers=headers,
    ).status_code == 422

    created = client.post(
        "/api/v1/users",
        json=_user_payload(role="REGIONAL_ADMIN", region="Yangon"),
        headers=headers,
    )
    assert created.status_code == 201, created.text
    data = created.json()["data"]
    # Region is actually stored now (it used to be silently dropped).
    assert data["region"] == "Yangon"

    # Clearing the region of a regional admin is refused.
    assert client.put(
        f"/api/v1/users/{data['id']}", json={"region": None}, headers=headers
    ).status_code == 422


def test_area_change_ends_existing_sessions(client, admin_token):
    headers = auth(admin_token)
    data = client.post(
        "/api/v1/users",
        json=_user_payload(role="REGIONAL_ADMIN", region="Yangon"),
        headers=headers,
    ).json()["data"]
    token = client.post(
        "/api/v1/auth/login",
        json={"username": "newuser", "password": "NewUser@123"},
    ).json()["data"]["access_token"]

    assert client.put(
        f"/api/v1/users/{data['id']}", json={"region": "Mandalay"}, headers=headers
    ).status_code == 200
    assert client.get("/api/v1/cctvs", headers=auth(token)).status_code == 401


def test_missing_password_is_422_not_500(client, admin_token):
    payload = _user_payload()
    del payload["password"]
    resp = client.post("/api/v1/users", json=payload, headers=auth(admin_token))
    assert resp.status_code == 422


def test_last_admin_protection_covers_overall_admin(client, db):
    # The only admin is stored as OVERALL_ADMIN (not the legacy ADMIN name).
    headers = _login_as(client, db, "boss", Role.OVERALL_ADMIN)
    other = client.post(
        "/api/v1/users", json=_user_payload(role="USER"), headers=headers
    ).json()["data"]
    assert other["role"] == "USER"

    me = db.users.find_one({"username": "boss"})
    assert user_service.count_admins(db) == 1
    with pytest.raises(ValidationError, match="last active admin"):
        user_service.update_user(db, str(me["_id"]), UserUpdate(role=Role.USER))
    with pytest.raises(ValidationError, match="last active admin"):
        user_service.delete_user(db, str(me["_id"]))


def test_admin_cannot_disable_self(client, admin_user, admin_token):
    resp = client.put(
        f"/api/v1/users/{admin_user['_id']}",
        json={"is_active": False},
        headers=auth(admin_token),
    )
    assert resp.status_code == 422


def test_resending_unchanged_role_is_not_a_role_change(client, admin_user, admin_token):
    resp = client.put(
        f"/api/v1/users/{admin_user['_id']}",
        json={"role": "ADMIN", "full_name": "Renamed"},
        headers=auth(admin_token),
    )
    assert resp.status_code == 200, resp.text


# --- Refresh tokens -------------------------------------------------------------


def _login_tokens(client, username="admin", password="Admin@12345"):
    return client.post(
        "/api/v1/auth/login", json={"username": username, "password": password}
    ).json()["data"]


def test_refresh_reuse_revokes_all_sessions(client, admin_user):
    first = _login_tokens(client)
    other_device = _login_tokens(client)

    rotated = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
    )
    assert rotated.status_code == 200

    # Replaying the spent token is treated as theft...
    assert client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
    ).status_code == 401
    # ...so every session of that user is revoked, including the new one
    # and the other device.
    for token in (
        rotated.json()["data"]["refresh_token"],
        other_device["refresh_token"],
    ):
        assert client.post(
            "/api/v1/auth/refresh", json={"refresh_token": token}
        ).status_code == 401


def test_refresh_rejects_oversized_token(client):
    resp = client.post("/api/v1/auth/refresh", json={"refresh_token": "x" * 10_000})
    assert resp.status_code == 422


def test_refresh_tokens_are_stored_hashed(client, db, admin_user):
    tokens = _login_tokens(client)
    stored = db.refresh_tokens.find_one({})
    assert stored["token_hash"] != tokens["refresh_token"]
    assert len(stored["token_hash"]) == 64  # SHA-256 hex
