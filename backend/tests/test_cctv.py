"""CCTV CRUD, search, filter, pagination and geospatial tests."""
from __future__ import annotations

import pytest

from tests.conftest import auth


def _payload(**overrides):
    base = {
        "cctv_id": "CCTV-YGN-000001",
        "latitude": 16.8409,
        "longitude": 96.1561,
        "region": "Yangon",
        "township": "Bahan",
        "street": "Main St",
        "status": "ACTIVE",
        "description": "Main intersection camera",
    }
    base.update(overrides)
    return base


def test_create_and_get(client, admin_token):
    created = client.post(
        "/api/v1/cctvs",
        json=_payload(direction="E", type="Dome"),
        headers=auth(admin_token),
    )
    assert created.status_code == 201
    data = created.json()["data"]
    assert data["cctv_id"] == "CCTV-YGN-000001"
    # GeoJSON order must be [longitude, latitude]; serialized back correctly.
    assert data["longitude"] == 96.1561
    assert data["latitude"] == 16.8409
    assert data["direction"] == "E"
    assert data["type"] == "Dome"

    fetched = client.get(
        f"/api/v1/cctvs/{data['id']}", headers=auth(admin_token)
    ).json()["data"]
    assert fetched["id"] == data["id"]
    assert fetched["direction"] == "E"
    assert fetched["type"] == "Dome"


def test_update_direction(client, admin_token):
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]

    updated = client.put(
        f"/api/v1/cctvs/{created['id']}",
        json={"direction": "NW"},
        headers=auth(admin_token),
    )

    assert updated.status_code == 200
    assert updated.json()["data"]["direction"] == "NW"


def test_create_and_update_rtsp_port(client, admin_token):
    created = client.post(
        "/api/v1/cctvs",
        json=_payload(rtsp_port=8554),
        headers=auth(admin_token),
    ).json()["data"]

    fetched = client.get(
        f"/api/v1/cctvs/{created['id']}", headers=auth(admin_token)
    ).json()["data"]
    assert fetched["rtsp_port"] == 8554

    updated = client.put(
        f"/api/v1/cctvs/{created['id']}",
        json={"rtsp_port": 9554},
        headers=auth(admin_token),
    )
    assert updated.status_code == 200
    assert updated.json()["data"]["rtsp_port"] == 9554

    fetched_after_update = client.get(
        f"/api/v1/cctvs/{created['id']}", headers=auth(admin_token)
    ).json()["data"]
    assert fetched_after_update["rtsp_port"] == 9554


def test_connection_test_persists_status_and_broadcasts_dashboard(
    client, admin_token, monkeypatch
):
    from app.services import cctv_service

    monkeypatch.setattr(cctv_service, "_encrypt_credential", lambda value: value)
    monkeypatch.setattr(cctv_service, "_decrypt_credential", lambda value: value)
    checked_settings = []

    def verify(ip_address, port, username, password):
        checked_settings.append((ip_address, port, username, password))
        return True

    monkeypatch.setattr(cctv_service, "verify_rtsp_connection", verify)
    created_response = client.post(
        "/api/v1/cctvs",
        json=_payload(
            ip_address="192.168.1.40",
            port=8554,
            username="camera-user",
            password="camera-pass",
        ),
        headers=auth(admin_token),
    )
    created = created_response.json()["data"]

    with client.websocket_connect("/api/v1/ws/dashboard") as websocket:
        websocket.send_json({"type": "authenticate", "token": admin_token})
        assert websocket.receive_json() == {"type": "connected"}

        response = client.post(
            f"/api/v1/cctvs/{created['id']}/test-connection",
            headers=auth(admin_token),
        )
        assert response.status_code == 200
        result = response.json()["data"]
        assert result["connected"] is True
        assert result["cctv"]["status"] == "ACTIVE"
        assert result["cctv"]["last_checked"] is not None
        assert "ip_address" not in result["cctv"]
        assert checked_settings == [
            ("192.168.1.40", 8554, "camera-user", "camera-pass")
        ]

        event = websocket.receive_json()
        assert event["type"] == "dashboard_update"
        assert event["cctv"]["id"] == created["id"]
        assert event["cctv"]["status"] == "ACTIVE"
        assert event["stats"]["active_cctv"] == 1


def test_connection_test_failure_marks_cctv_inactive(
    client, admin_token, monkeypatch
):
    from app.services import cctv_service

    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]
    monkeypatch.setattr(
        cctv_service, "verify_rtsp_connection", lambda *args: False
    )

    response = client.post(
        f"/api/v1/cctvs/{created['id']}/test-connection",
        headers=auth(admin_token),
    )

    assert response.status_code == 200
    assert response.json()["data"]["connected"] is False
    assert response.json()["data"]["cctv"]["status"] == "INACTIVE"
    assert response.json()["data"]["cctv"]["last_checked"] is not None


def test_connection_test_rejects_non_object_id(client, admin_token):
    response = client.post(
        "/api/v1/cctvs/CCTV-YGN-000001/test-connection",
        headers=auth(admin_token),
    )

    assert response.status_code == 422
    assert "MongoDB record ID" in response.json()["error"]["message"]
    assert "display ID" in response.json()["error"]["message"]


def test_connection_test_reports_missing_object_id(client, admin_token):
    from bson import ObjectId

    missing_id = str(ObjectId())
    response = client.post(
        f"/api/v1/cctvs/{missing_id}/test-connection",
        headers=auth(admin_token),
    )

    assert response.status_code == 404
    assert missing_id in response.json()["error"]["message"]
    assert "No CCTV record was found" in response.json()["error"]["message"]


def test_update_all_editable_cctv_fields(client, admin_token):
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]

    updated = client.put(
        f"/api/v1/cctvs/{created['id']}",
        json={
            "cctv_id": "CCTV-MDY-000002",
            "latitude": 21.9588,
            "longitude": 96.0891,
            "region": "Mandalay",
            "township": "Chanayethazan",
            "street": "Palace Road",
            "direction": "W",
            "status": "MAINTENANCE",
            "description": "Updated camera",
        },
        headers=auth(admin_token),
    )

    assert updated.status_code == 200
    data = updated.json()["data"]
    assert data["cctv_id"] == "CCTV-MDY-000002"
    assert (data["latitude"], data["longitude"]) == (21.9588, 96.0891)
    assert data["region"] == "Mandalay"
    assert data["township"] == "Chanayethazan"
    assert data["street"] == "Palace Road"
    assert data["direction"] == "W"
    assert data["status"] == "MAINTENANCE"
    assert data["description"] == "Updated camera"


def test_credentials_are_encrypted_and_only_returned_for_detail(
    client, db, admin_token, monkeypatch
):
    import secrets

    from app.services import cctv_service

    monkeypatch.setattr(
        cctv_service.settings,
        "CCTV_CREDENTIALS_ENCRYPTION_KEY",
        secrets.token_urlsafe(32),
    )
    created = client.post(
        "/api/v1/cctvs",
        json=_payload(
            ip_address="192.168.1.25",
            username="stream-user",
            password="camera-secret",
            tags=["ALPRS", "CPCS"],
        ),
        headers=auth(admin_token),
    )
    assert created.status_code == 201, created.text
    record_id = created.json()["data"]["id"]
    stored = cctv_service.get_by_id(db, record_id)
    assert stored["ip_address"].startswith("enc:v1:")
    assert stored["username"].startswith("enc:v1:")
    assert stored["password"].startswith("enc:v1:")
    assert "camera-secret" not in str(stored)

    listed = client.get("/api/v1/cctvs", headers=auth(admin_token))
    list_record = listed.json()["data"]["items"][0]
    assert "ip_address" not in list_record
    assert "username" not in list_record
    assert "password" not in list_record

    detail = client.get(f"/api/v1/cctvs/{record_id}", headers=auth(admin_token))
    assert detail.status_code == 200
    data = detail.json()["data"]
    assert data["ip_address"] == "192.168.1.25"
    assert data["username"] == "stream-user"
    assert data["password"] == "camera-secret"
    assert data["tags"] == ["ALPRS", "CPCS"]

    updated = client.put(
        f"/api/v1/cctvs/{record_id}",
        json={
            "ip_address": "10.0.0.8",
            "username": "updated-user",
            "password": "updated-secret",
            "description": "Updated description",
            "tags": ["FRS", "ARDS"],
        },
        headers=auth(admin_token),
    )
    assert updated.status_code == 200, updated.text
    stored = cctv_service.get_by_id(db, record_id)
    assert "updated-secret" not in str(stored)
    updated_detail = client.get(
        f"/api/v1/cctvs/{record_id}", headers=auth(admin_token)
    ).json()["data"]
    assert updated_detail["ip_address"] == "10.0.0.8"
    assert updated_detail["username"] == "updated-user"
    assert updated_detail["password"] == "updated-secret"
    assert updated_detail["description"] == "Updated description"
    assert updated_detail["tags"] == ["FRS", "ARDS"]

@pytest.mark.parametrize(
    "overrides",
    [
        {"ip_address": "not-an-ip"},
        {"tags": ["UNKNOWN"]},
        {"tags": ["FRS", "FRS"]},
    ],
)
def test_invalid_ip_address_or_tags_rejected(client, admin_token, overrides):
    response = client.post(
        "/api/v1/cctvs",
        json=_payload(**overrides),
        headers=auth(admin_token),
    )
    assert response.status_code == 422


def test_serialize_marker_includes_direction():
    from bson import ObjectId

    from app.services.cctv_service import serialize_marker

    marker = serialize_marker(
        {
            "_id": ObjectId(),
            "cctv_id": "CCTV-YGN-000001",
            "location": {"type": "Point", "coordinates": [96.1561, 16.8409]},
            "direction": "E",
            "status": "ACTIVE",
        }
    )

    assert marker["direction"] == "E"


def test_duplicate_cctv_id_conflict(client, admin_token):
    client.post("/api/v1/cctvs", json=_payload(), headers=auth(admin_token))
    dup = client.post(
        "/api/v1/cctvs",
        json=_payload(latitude=16.9, longitude=96.2),
        headers=auth(admin_token),
    )
    assert dup.status_code == 409


def test_invalid_coordinates_rejected(client, admin_token):
    assert (
        client.post(
            "/api/v1/cctvs",
            json=_payload(latitude=200),
            headers=auth(admin_token),
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/cctvs",
            json=_payload(longitude=-500),
            headers=auth(admin_token),
        ).status_code
        == 422
    )


def test_search_and_filter(client, admin_token):
    client.post("/api/v1/cctvs", json=_payload(), headers=auth(admin_token))
    client.post(
        "/api/v1/cctvs",
        json=_payload(
            cctv_id="CCTV-MDY-000001",
            region="Mandalay",
            township="Chanayethazan",
            status="INACTIVE",
        ),
        headers=auth(admin_token),
    )

    by_search = client.get(
        "/api/v1/cctvs?search=MDY", headers=auth(admin_token)
    ).json()["data"]
    assert by_search["pagination"]["total"] == 1

    by_status = client.get(
        "/api/v1/cctvs?status=INACTIVE", headers=auth(admin_token)
    ).json()["data"]
    assert by_status["pagination"]["total"] == 1

    by_township = client.get(
        "/api/v1/cctvs?township=Bahan", headers=auth(admin_token)
    ).json()["data"]
    assert by_township["pagination"]["total"] == 1


def test_filter_by_type(client, admin_token):
    client.post(
        "/api/v1/cctvs",
        json=_payload(type="Dome"),
        headers=auth(admin_token),
    )
    client.post(
        "/api/v1/cctvs",
        json=_payload(cctv_id="CCTV-MDY-000001", type="Bullet"),
        headers=auth(admin_token),
    )

    filtered = client.get(
        "/api/v1/cctvs?type=Dome", headers=auth(admin_token)
    )

    assert filtered.status_code == 200
    data = filtered.json()["data"]
    assert data["pagination"]["total"] == 1
    assert data["items"][0]["cctv_id"] == "CCTV-YGN-000001"

    searched = client.get(
        "/api/v1/cctvs?search=Dome", headers=auth(admin_token)
    )

    assert searched.status_code == 200
    searched_data = searched.json()["data"]
    assert searched_data["pagination"]["total"] == 1
    assert searched_data["items"][0]["cctv_id"] == "CCTV-YGN-000001"


def test_filter_by_tag(client, admin_token):
    client.post(
        "/api/v1/cctvs",
        json=_payload(tags=["ALPRS"]),
        headers=auth(admin_token),
    )
    client.post(
        "/api/v1/cctvs",
        json=_payload(cctv_id="CCTV-MDY-000001", tags=["CPCS"]),
        headers=auth(admin_token),
    )
    client.post(
        "/api/v1/cctvs",
        json=_payload(cctv_id="CCTV-BAG-000001", tags=["FRS"]),
        headers=auth(admin_token),
    )

    for tag, expected in (
        ("ALPRS", "CCTV-YGN-000001"),
        ("CPCS", "CCTV-MDY-000001"),
    ):
        filtered = client.get(
            f"/api/v1/cctvs?tag={tag}", headers=auth(admin_token)
        )
        assert filtered.status_code == 200
        data = filtered.json()["data"]
        assert data["pagination"]["total"] == 1
        assert data["items"][0]["cctv_id"] == expected
        assert tag in data["items"][0]["tags"]

    no_matches = client.get(
        "/api/v1/cctvs?tag=ARDS", headers=auth(admin_token)
    ).json()["data"]
    assert no_matches["items"] == []
    assert no_matches["pagination"]["total"] == 0

    multiple = client.get(
        "/api/v1/cctvs?tag=ALPRS,FRS", headers=auth(admin_token)
    )
    assert multiple.status_code == 200
    multiple_data = multiple.json()["data"]
    assert multiple_data["pagination"]["total"] == 2
    assert {item["cctv_id"] for item in multiple_data["items"]} == {
        "CCTV-YGN-000001",
        "CCTV-BAG-000001",
    }

    invalid = client.get("/api/v1/cctvs?tag=UNKNOWN", headers=auth(admin_token))
    assert invalid.status_code == 422
    all_records = client.get("/api/v1/cctvs?tag=All", headers=auth(admin_token))
    assert all_records.status_code == 200
    assert all_records.json()["data"]["pagination"]["total"] == 3
    for invalid_tags in ("ALPRS,", "ALPRS,UNKNOWN"):
        assert client.get(
            f"/api/v1/cctvs?tag={invalid_tags}", headers=auth(admin_token)
        ).status_code == 422


def test_filter_by_multiple_statuses(client, admin_token):
    for i, status in enumerate(["ACTIVE", "INACTIVE", "MAINTENANCE"]):
        client.post(
            "/api/v1/cctvs",
            json=_payload(
                cctv_id=f"CCTV-YGN-00000{i + 1}",
                latitude=16.8 + i / 100,
                status=status,
            ),
            headers=auth(admin_token),
        )

    def total(query):
        resp = client.get(f"/api/v1/cctvs?{query}", headers=auth(admin_token))
        assert resp.status_code == 200, resp.text
        return resp.json()["data"]["pagination"]["total"]

    assert total("status=ACTIVE,MAINTENANCE") == 2
    assert total("status=ACTIVE,INACTIVE,MAINTENANCE") == 3
    assert total("status=INACTIVE") == 1
    # Unknown values and malformed lists are still rejected.
    for bad in ("status=ACTIVE,BOGUS", "status=ACTIVE,", "status=active"):
        assert client.get(
            f"/api/v1/cctvs?{bad}", headers=auth(admin_token)
        ).status_code == 422


def test_pagination(client, admin_token):
    for i in range(5):
        client.post(
            "/api/v1/cctvs",
            json=_payload(cctv_id=f"CCTV-YGN-{i:06d}", longitude=96.0 + i * 0.001),
            headers=auth(admin_token),
        )
    page1 = client.get(
        "/api/v1/cctvs?page=1&limit=2", headers=auth(admin_token)
    ).json()["data"]
    assert len(page1["items"]) == 2
    assert page1["pagination"]["total"] == 5
    assert page1["pagination"]["has_next"] is True

    page3 = client.get(
        "/api/v1/cctvs?page=3&limit=2", headers=auth(admin_token)
    ).json()["data"]
    assert len(page3["items"]) == 1
    assert page3["pagination"]["has_next"] is False


def test_limit_exceeds_max_rejected(client, admin_token):
    assert (
        client.get("/api/v1/cctvs?limit=1000", headers=auth(admin_token)).status_code
        == 422
    )


def test_stats_aggregation(client, admin_token):
    client.post("/api/v1/cctvs", json=_payload(), headers=auth(admin_token))
    client.post(
        "/api/v1/cctvs",
        json=_payload(cctv_id="CCTV-YGN-000002", status="INACTIVE"),
        headers=auth(admin_token),
    )
    stats = client.get("/api/v1/cctvs/stats", headers=auth(admin_token)).json()["data"]
    assert stats["total_cctv"] == 2
    assert stats["active_cctv"] == 1
    assert stats["inactive_cctv"] == 1
    assert stats["added_today"] == 2


def test_nearby_rejects_invalid_radius(client, admin_token):
    resp = client.get(
        "/api/v1/cctvs/nearby?latitude=16.84&longitude=96.15&radius_meters=0",
        headers=auth(admin_token),
    )
    assert resp.status_code == 422


def test_nearby_builds_geospatial_query(monkeypatch):
    """Verify the service issues a $near query with correct coordinates.

    mongomock does not implement $near, so we assert on the query shape
    instead of executing it.
    """
    from app.services import cctv_service

    captured: dict = {}

    class _Cursor:
        def limit(self, _n):
            return []

    class _Collection:
        def find(self, query):
            captured["query"] = query
            return _Cursor()

    class _DB:
        cctvs = _Collection()

    from types import SimpleNamespace

    from app.core.rbac import Role

    regional = SimpleNamespace(
        id="u1", role=Role.REGIONAL_ADMIN, region="Yangon", township=None
    )
    cctv_service.nearby(
        _DB(),
        latitude=16.8409,
        longitude=96.1561,
        radius_meters=500,
        limit=10,
        user=regional,
    )
    query = captured["query"]
    near = query["location"]["$near"]
    assert near["$maxDistance"] == 500
    # GeoJSON order: [longitude, latitude]
    assert near["$geometry"]["coordinates"] == [96.1561, 16.8409]
    # Scope is applied alongside the (top-level) $near predicate.
    assert query["region"] == "Yangon"


def test_schema_geojson_order():
    from app.services.cctv_service import to_geojson

    point = to_geojson(96.1561, 16.8409)
    assert point["coordinates"] == [96.1561, 16.8409]
