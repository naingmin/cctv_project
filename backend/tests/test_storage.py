"""Object storage tests.

Presigned URL signing is pure local HMAC, so it is exercised against real boto3
without a running MinIO. Anything that would touch the network (head, delete,
put) is stubbed.
"""
from __future__ import annotations

import re
from urllib.parse import parse_qs, urlparse

import pytest

from app.core.errors import ValidationError
from app.services import storage_service
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
    }
    base.update(overrides)
    return base


@pytest.fixture(autouse=True)
def _public_endpoint(monkeypatch):
    """Sign against a distinct host so tests can assert it is honoured."""
    monkeypatch.setattr(
        storage_service.settings, "MINIO_PUBLIC_ENDPOINT", "http://minio.test:9000",
        raising=False,
    )
    storage_service.reset_clients()
    yield
    storage_service.reset_clients()


class _StubS3:
    """Minimal stand-in for the boto3 S3 client."""

    def __init__(self, *, exists=True, size=1024):
        self._exists = exists
        self._size = size
        self.deleted: list[str] = []
        self.head_calls: list[str] = []

    def head_object(self, Bucket, Key):  # noqa: N803 (boto3 casing)
        self.head_calls.append(Key)
        if not self._exists:
            from botocore.exceptions import ClientError

            raise ClientError(
                {"Error": {"Code": "404", "Message": "Not Found"}}, "HeadObject"
            )
        return {"ContentLength": self._size}

    def delete_object(self, Bucket, Key):  # noqa: N803
        self.deleted.append(Key)
        return {}


# --------------------------------------------------------------------------
# Key construction and validation
# --------------------------------------------------------------------------


def test_object_key_is_server_controlled_and_scoped():
    key = storage_service.build_object_key("CCTV-YGN-000001", "CCTV_VIEW", ".jpg")
    assert key.startswith("cctv/CCTV-YGN-000001/view/")
    assert key.endswith(".jpg")
    # Randomised, so two uploads never collide or overwrite.
    other = storage_service.build_object_key("CCTV-YGN-000001", "CCTV_VIEW", ".jpg")
    assert key != other


def test_object_key_strips_path_characters_from_id():
    key = storage_service.build_object_key("../../etc", "ENVIRONMENT", ".png")
    # The id is sanitised down to alphanumerics, so no traversal survives.
    assert ".." not in key
    assert key.startswith("cctv/etc/environment/")


def test_object_key_folder_matches_image_type():
    view = storage_service.build_object_key("A1", "CCTV_VIEW", ".jpg")
    env = storage_service.build_object_key("A1", "ENVIRONMENT", ".jpg")
    assert "/view/" in view
    assert "/environment/" in env


@pytest.mark.parametrize(
    "content_type,filename",
    [
        ("image/gif", "a.gif"),
        ("application/pdf", "a.pdf"),
        ("", "a.jpg"),
        # Extension is not in the allow-list even if the MIME type is.
        ("image/jpeg", "a.svg"),
    ],
)
def test_validate_content_type_rejects(content_type, filename):
    with pytest.raises(ValidationError):
        storage_service.validate_content_type(content_type, filename)


def test_validate_content_type_accepts_allowed_types():
    assert storage_service.validate_content_type("image/png", "a.png") == "image/png"
    assert storage_service.validate_content_type("IMAGE/WEBP", "a.webp") == "image/webp"


# --------------------------------------------------------------------------
# Presigned URLs - real boto3 signing, no network
# --------------------------------------------------------------------------


def test_presigned_put_url_is_signed_and_uses_public_endpoint():
    url = storage_service.presigned_put_url("cctv/a/view/x.jpg", 300, "image/jpeg")
    parsed = urlparse(url)

    assert parsed.scheme == "http"
    # Signed for the client-visible host, not the internal one.
    assert parsed.netloc == "minio.test:9000"
    assert "/cctv-media/" in parsed.path

    query = parse_qs(parsed.query)
    assert "X-Amz-Signature" in query
    assert query["X-Amz-Expires"] == ["300"]
    # boto3 records signed headers in X-Amz-SignedHeaders, so MinIO rejects a
    # PUT whose Content-Type differs from the one declared here.
    assert "content-type" in query["X-Amz-SignedHeaders"][0].lower()


def test_presigned_get_url_is_signed():
    url = storage_service.presigned_get_url("cctv/a/view/x.jpg", 120)
    parsed = urlparse(url)
    query = parse_qs(parsed.query)

    assert parsed.netloc == "minio.test:9000"
    assert "X-Amz-Signature" in query
    assert query["X-Amz-Expires"] == ["120"]


def test_presigned_urls_differ_per_key():
    a = storage_service.presigned_get_url("cctv/a/view/1.jpg", 300)
    b = storage_service.presigned_get_url("cctv/a/view/2.jpg", 300)
    assert a != b


def test_content_type_is_inside_the_signature():
    """Changing the declared type must change the signature.

    This is the offline stand-in for what MinIO enforces at runtime: if the
    content type is part of the signed canonical request, a client that PUTs
    different bytes under a different declared type gets SignatureDoesNotMatch.
    """
    png = storage_service.presigned_put_url("cctv/a/view/x.png", 300, "image/png")
    jpeg = storage_service.presigned_put_url("cctv/a/view/x.png", 300, "image/jpeg")

    sig = lambda u: parse_qs(urlparse(u).query)["X-Amz-Signature"][0]
    assert sig(png) != sig(jpeg)


def test_expiry_is_inside_the_signature():
    """A tampered expiry must invalidate the URL."""
    sig = lambda u: parse_qs(urlparse(u).query)["X-Amz-Signature"][0]
    assert sig(storage_service.presigned_get_url("k", 300)) != sig(
        storage_service.presigned_get_url("k", 900)
    )


def test_presigned_url_carries_no_bearer_token():
    """The URL must not leak the API's credentials - only storage creds."""
    url = storage_service.presigned_get_url("cctv/a/view/x.jpg", 300)
    assert "Authorization" not in url
    assert "X-Amz-Security-Token" not in url


def test_put_url_signs_only_the_declared_content_type():
    """Omitting content type must not silently sign every type."""
    with_type = storage_service.presigned_put_url("k", 300, "image/png")
    without = storage_service.presigned_put_url("k", 300)
    assert "content-type" in parse_qs(urlparse(with_type).query)["X-Amz-SignedHeaders"][0].lower()
    assert "content-type" not in parse_qs(urlparse(without).query)["X-Amz-SignedHeaders"][0].lower()


# --------------------------------------------------------------------------
# Object operations (stubbed client)
# --------------------------------------------------------------------------


def test_object_exists_true_and_false(monkeypatch):
    stub = _StubS3(exists=True)
    monkeypatch.setattr(storage_service, "_get_client", lambda: stub)
    assert storage_service.object_exists("cctv/a/view/x.jpg") is True

    missing = _StubS3(exists=False)
    monkeypatch.setattr(storage_service, "_get_client", lambda: missing)
    assert storage_service.object_exists("cctv/a/view/x.jpg") is False


def test_remove_object_deletes(monkeypatch):
    stub = _StubS3()
    monkeypatch.setattr(storage_service, "_get_client", lambda: stub)
    storage_service.remove_object("cctv/a/view/x.jpg")
    assert stub.deleted == ["cctv/a/view/x.jpg"]


def test_get_object_size_reads_real_length(monkeypatch):
    stub = _StubS3(size=2048)
    monkeypatch.setattr(storage_service, "_get_client", lambda: stub)
    assert storage_service.get_object_size("cctv/a/view/x.jpg") == 2048


# --------------------------------------------------------------------------
# Endpoints
# --------------------------------------------------------------------------


def test_presign_returns_absolute_upload_url(client, admin_token):
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]

    resp = client.post(
        "/api/v1/uploads/presign",
        json={
            "cctv_id": created["id"],
            "image_type": "CCTV_VIEW",
            "filename": "shot.jpg",
            "content_type": "image/jpeg",
        },
        headers=auth(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()["data"]

    # Must be absolute so the client can PUT to it directly.
    assert data["upload_url"].startswith("http")
    assert "X-Amz-Signature" in data["upload_url"]
    assert data["object_key"].startswith("cctv/CCTV-YGN-000001/view/")


def test_local_upload_endpoints_are_gone(client, admin_token):
    """The proxy endpoints were removed in favour of direct uploads."""
    assert (
        client.post(
            "/api/v1/uploads/local/put",
            headers=auth(admin_token),
        ).status_code
        == 404
    )
    assert (
        client.get(
            "/api/v1/uploads/local/get?key=cctv/a.jpg", headers=auth(admin_token)
        ).status_code
        == 404
    )


def test_complete_rejects_missing_object(client, admin_token, monkeypatch):
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]
    monkeypatch.setattr(storage_service, "object_exists", lambda key: False)

    resp = client.post(
        f"/api/v1/cctvs/{created['id']}/images/complete",
        json={
            "object_key": f"cctv/CCTV-YGN-000001/view/{created['id']}.jpg",
            "image_type": "CCTV_VIEW",
            "mime_type": "image/jpeg",
        },
        headers=auth(admin_token),
    )
    assert resp.status_code == 422
    # 422 is this codebase's validation-error status.


def test_complete_rejects_oversized_and_deletes_object(
    client, admin_token, monkeypatch
):
    """Bytes reach MinIO directly, so size is enforced after the fact."""
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]
    stub = _StubS3(exists=True, size=999 * 1024 * 1024)
    monkeypatch.setattr(storage_service, "object_exists", lambda key: True)
    monkeypatch.setattr(storage_service, "_get_client", lambda: stub)

    resp = client.post(
        f"/api/v1/cctvs/{created['id']}/images/complete",
        json={
            "object_key": f"cctv/CCTV-YGN-000001/view/{created['id']}.jpg",
            "image_type": "CCTV_VIEW",
            "mime_type": "image/jpeg",
        },
        headers=auth(admin_token),
    )
    assert resp.status_code == 422
    # The oversized object must not be left behind in the bucket.
    assert stub.deleted == [f"cctv/CCTV-YGN-000001/view/{created['id']}.jpg"]


def test_complete_records_real_size_not_client_claim(
    client, admin_token, monkeypatch
):
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]
    monkeypatch.setattr(storage_service, "object_exists", lambda key: True)
    monkeypatch.setattr(storage_service, "get_object_size", lambda key: 4096)

    resp = client.post(
        f"/api/v1/cctvs/{created['id']}/images/complete",
        json={
            "object_key": f"cctv/CCTV-YGN-000001/view/{created['id']}.jpg",
            "image_type": "CCTV_VIEW",
            "mime_type": "image/jpeg",
            "file_size": 1,  # deliberately wrong
        },
        headers=auth(admin_token),
    )
    assert resp.status_code == 201
    assert resp.json()["data"]["file_size"] == 4096


def test_complete_rejects_foreign_object_key(client, admin_token, monkeypatch):
    """A key from another record must not be attachable to this one."""
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]
    monkeypatch.setattr(storage_service, "object_exists", lambda key: True)
    monkeypatch.setattr(storage_service, "get_object_size", lambda key: 10)

    resp = client.post(
        f"/api/v1/cctvs/{created['id']}/images/complete",
        json={
            "object_key": "cctv/CCTV-YGN-999999/view/other.jpg",
            "image_type": "CCTV_VIEW",
            "mime_type": "image/jpeg",
        },
        headers=auth(admin_token),
    )
    assert resp.status_code == 403


def test_image_urls_resolves_every_image_in_one_call(client, admin_token, monkeypatch):
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]
    monkeypatch.setattr(storage_service, "object_exists", lambda key: True)
    monkeypatch.setattr(storage_service, "get_object_size", lambda key: 10)

    ids = []
    for image_type in ("CCTV_VIEW", "ENVIRONMENT"):
        resp = client.post(
            f"/api/v1/cctvs/{created['id']}/images/complete",
            json={
                "object_key": (
                    f"cctv/CCTV-YGN-000001/view/{image_type}.jpg"
                    if image_type == "CCTV_VIEW"
                    else f"cctv/CCTV-YGN-000001/environment/{image_type}.jpg"
                ),
                "image_type": image_type,
                "mime_type": "image/jpeg",
            },
            headers=auth(admin_token),
        )
        assert resp.status_code == 201
        ids.append(resp.json()["data"]["id"])

    resp = client.get(
        f"/api/v1/cctvs/{created['id']}/images/urls", headers=auth(admin_token)
    )
    assert resp.status_code == 200
    urls = resp.json()["data"]["urls"]

    assert set(urls) == set(ids)
    for url in urls.values():
        assert "X-Amz-Signature" in url


def test_record_carries_presigned_view_url(client, admin_token, monkeypatch):
    """List and detail payloads sign the primary image, so cards can render."""
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]
    monkeypatch.setattr(storage_service, "object_exists", lambda key: True)
    monkeypatch.setattr(storage_service, "get_object_size", lambda key: 10)

    client.post(
        f"/api/v1/cctvs/{created['id']}/images/complete",
        json={
            "object_key": "cctv/CCTV-YGN-000001/view/main.jpg",
            "image_type": "CCTV_VIEW",
            "mime_type": "image/jpeg",
        },
        headers=auth(admin_token),
    )

    fetched = client.get(
        f"/api/v1/cctvs/{created['id']}", headers=auth(admin_token)
    ).json()["data"]
    assert fetched["view_image_url"]
    assert "X-Amz-Signature" in fetched["view_image_url"]

    listing = client.get("/api/v1/cctvs", headers=auth(admin_token)).json()["data"]
    assert listing["items"][0]["view_image_url"]


def test_view_image_url_is_null_without_images(client, admin_token):
    created = client.post(
        "/api/v1/cctvs", json=_payload(), headers=auth(admin_token)
    ).json()["data"]
    fetched = client.get(
        f"/api/v1/cctvs/{created['id']}", headers=auth(admin_token)
    ).json()["data"]
    assert fetched["view_image_url"] is None
