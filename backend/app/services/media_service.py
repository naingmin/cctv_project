"""MediaMTX path registration and client playback URLs."""
from __future__ import annotations

import json
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

from app.config import settings
from app.core.errors import ServiceUnavailableError


_REQUEST_TIMEOUT_SECONDS = 5


def _request(
    method: str, api_path: str, payload: dict | None = None
) -> bool:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = Request(
        f"{settings.MEDIAMTX_API_URL.rstrip('/')}{api_path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    try:
        with urlopen(request, timeout=_REQUEST_TIMEOUT_SECONDS) as response:
            response.read()
        return True
    except HTTPError as exc:
        if method == "GET" and exc.code == 404:
            return False
        raise ServiceUnavailableError(
            "MediaMTX could not configure the camera stream."
        ) from exc
    except URLError as exc:
        raise ServiceUnavailableError(
            "MediaMTX is unavailable. Please try again later."
        ) from exc
    except TimeoutError as exc:
        raise ServiceUnavailableError(
            "MediaMTX did not respond in time. Please try again."
        ) from exc


def configure_stream(stream_path: str, source_url: str) -> dict[str, str]:
    """Create or refresh an on-demand RTSP source and return playback URLs."""
    encoded_path = quote(stream_path, safe="")
    api_path = f"/v3/config/paths/get/{encoded_path}"
    exists = _request("GET", api_path)
    if exists:
        _request(
            "PUT",
            f"/v3/config/paths/replace/{encoded_path}",
            {"source": source_url, "sourceOnDemand": True},
        )
    else:
        _request(
            "POST",
            f"/v3/config/paths/add/{encoded_path}",
            {"source": source_url, "sourceOnDemand": True},
        )

    return {
        "stream_path": stream_path,
        "whep_url": (
            f"{settings.MEDIAMTX_WHEP_BASE_URL.rstrip('/')}/"
            f"{encoded_path}/whep"
        ),
        "hls_url": (
            f"{settings.MEDIAMTX_HLS_BASE_URL.rstrip('/')}/"
            f"{encoded_path}/index.m3u8"
        ),
    }
