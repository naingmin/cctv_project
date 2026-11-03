from __future__ import annotations

from types import SimpleNamespace

import pytest
from requests.exceptions import Timeout
from zeep.exceptions import Fault

from app.schemas.cctv import ONVIFDiscoverRequest
from app.services import cctv_service
from tests.conftest import auth


def test_onvif_discover_request_defaults_and_normalizes_ip():
    request = ONVIFDiscoverRequest(
        ip="192.168.1.20", username="camera-user", password="camera-pass"
    )

    assert request.ip == "192.168.1.20"
    assert request.port == 80


def test_onvif_discover_request_rejects_hostnames():
    with pytest.raises(ValueError, match="valid IPv4 or IPv6"):
        ONVIFDiscoverRequest(
            ip="camera.local", username="camera-user", password="camera-pass"
        )


def test_discover_onvif_returns_first_profile_uri(monkeypatch):
    profile_tokens = []

    class FakeMediaService:
        def GetProfiles(self):
            return [SimpleNamespace(token="profile-1")]

        def GetStreamUri(self, request):
            profile_tokens.append(request["ProfileToken"])
            return SimpleNamespace(Uri="rtsp://192.168.1.20/live")

    class FakeCamera:
        def __init__(self, ip, port, username, password, *, transport):
            assert (ip, port, username, password) == (
                "192.168.1.20",
                8000,
                "camera-user",
                "camera-pass",
            )
            assert transport is not None

        def create_media_service(self):
            return FakeMediaService()

    monkeypatch.setattr(cctv_service, "ONVIFCamera", FakeCamera)

    result = cctv_service.discover_onvif_rtsp_url(
        "192.168.1.20", 8000, "camera-user", "camera-pass"
    )

    assert result == "rtsp://192.168.1.20/live"
    assert profile_tokens == ["profile-1"]


def test_discover_onvif_raises_timeout_error(monkeypatch):
    def timeout(*args, **kwargs):
        raise Timeout()

    monkeypatch.setattr(cctv_service, "ONVIFCamera", timeout)

    with pytest.raises(cctv_service.ONVIFTimeoutError):
        cctv_service.discover_onvif_rtsp_url(
            "192.168.1.20", 80, "camera-user", "camera-pass"
        )


def test_discover_onvif_maps_authentication_fault(monkeypatch):
    class FakeMediaService:
        def GetProfiles(self):
            raise Fault("NotAuthorized")

    class FakeCamera:
        def __init__(self, *args, **kwargs):
            pass

        def create_media_service(self):
            return FakeMediaService()

    monkeypatch.setattr(cctv_service, "ONVIFCamera", FakeCamera)

    with pytest.raises(cctv_service.ONVIFAuthenticationError):
        cctv_service.discover_onvif_rtsp_url(
            "192.168.1.20", 80, "camera-user", "camera-pass"
        )


def test_onvif_endpoint_returns_rtsp_url(client, admin_token, monkeypatch):
    received = []

    def discover(ip, port, username, password):
        received.append((ip, port, username, password))
        return "rtsp://192.168.1.20/live"

    monkeypatch.setattr(cctv_service, "discover_onvif_rtsp_url", discover)

    response = client.post(
        "/api/v1/cctv/discover-onvif",
        json={
            "ip": "192.168.1.20",
            "username": "camera-user",
            "password": "camera-pass",
        },
        headers=auth(admin_token),
    )

    assert response.status_code == 200
    assert response.json() == {
        "success": True,
        "data": {"rtsp_url": "rtsp://192.168.1.20/live"},
        "message": "ONVIF discovery completed.",
    }
    assert received == [
        ("192.168.1.20", 80, "camera-user", "camera-pass")
    ]


@pytest.mark.parametrize(
    ("failure", "status_code", "message"),
    [
        (
            cctv_service.ONVIFAuthenticationError("Camera credentials were rejected."),
            502,
            "Camera credentials were rejected.",
        ),
        (
            cctv_service.ONVIFTimeoutError("Camera timed out."),
            504,
            "Camera timed out.",
        ),
    ],
)
def test_onvif_endpoint_reports_camera_errors(
    client, admin_token, monkeypatch, failure, status_code, message
):
    def fail(*args, **kwargs):
        raise failure

    monkeypatch.setattr(cctv_service, "discover_onvif_rtsp_url", fail)

    response = client.post(
        "/api/v1/cctv/discover-onvif",
        json={
            "ip": "192.168.1.20",
            "username": "camera-user",
            "password": "camera-pass",
        },
        headers=auth(admin_token),
    )

    assert response.status_code == status_code
    assert response.json()["success"] is False
    assert response.json()["error"]["message"] == message


def test_onvif_endpoint_requires_authentication(client):
    response = client.post(
        "/api/v1/cctv/discover-onvif",
        json={
            "ip": "192.168.1.20",
            "username": "camera-user",
            "password": "camera-pass",
        },
    )

    assert response.status_code == 401
