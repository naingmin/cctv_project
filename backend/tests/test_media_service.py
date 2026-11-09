"""MediaMTX path setup tests."""

from app.config import settings
from app.services import media_service


def test_configure_stream_adds_path_and_builds_client_urls(monkeypatch):
    monkeypatch.setattr(
        settings, "MEDIAMTX_API_URL", "http://mediamtx:9997/"
    )
    monkeypatch.setattr(
        settings, "MEDIAMTX_WHEP_BASE_URL", "https://streams.example/webrtc/"
    )
    monkeypatch.setattr(
        settings, "MEDIAMTX_HLS_BASE_URL", "https://streams.example/hls/"
    )
    requests = []
    responses = iter((False, True))

    def request(method, path, payload=None):
        requests.append((method, path, payload))
        return next(responses)

    monkeypatch.setattr(media_service, "_request", request)

    result = media_service.configure_stream(
        "cctv-507f1f77bcf86cd799439011",
        "rtsp://user:secret@camera.example/live",
    )

    encoded_path = "cctv-507f1f77bcf86cd799439011"
    assert requests == [
        ("GET", f"/v3/config/paths/get/{encoded_path}", None),
        (
            "POST",
            f"/v3/config/paths/add/{encoded_path}",
            {
                "source": "rtsp://user:secret@camera.example/live",
                "sourceOnDemand": True,
            },
        ),
    ]
    assert result == {
        "stream_path": encoded_path,
        "whep_url": f"https://streams.example/webrtc/{encoded_path}/whep",
        "hls_url": (
            f"https://streams.example/hls/{encoded_path}/index.m3u8"
        ),
    }


def test_configure_stream_replaces_existing_path(monkeypatch):
    responses = iter((True, True))
    requests = []

    def request(method, path, payload=None):
        requests.append(method)
        return next(responses)

    monkeypatch.setattr(media_service, "_request", request)

    media_service.configure_stream("cctv-1", "rtsp://camera.example/live")

    assert requests == ["GET", "PUT"]
