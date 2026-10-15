"""Production must refuse to start with default or placeholder secrets."""
import secrets

import pytest
from pydantic import ValidationError

from app.config import Settings


def _secure(**overrides):
    values = dict(
        ENVIRONMENT="production",
        DEBUG=False,
        JWT_SECRET_KEY=secrets.token_urlsafe(64),
        MONGODB_USERNAME="cctv-" + secrets.token_hex(6),
        MONGODB_PASSWORD=secrets.token_urlsafe(32),
        MINIO_ACCESS_KEY="cctv-" + secrets.token_hex(6),
        MINIO_SECRET_KEY=secrets.token_urlsafe(32),
        DEFAULT_ADMIN_PASSWORD="S0me-unique-passphrase",
        CCTV_CREDENTIALS_ENCRYPTION_KEY=secrets.token_urlsafe(32),
    )
    values.update(overrides)
    # _env_file=None: never let the developer's real .env leak into the test.
    return Settings(_env_file=None, **values)


def test_secure_production_config_is_accepted():
    assert _secure().is_production


@pytest.mark.parametrize(
    "override",
    [
        {"JWT_SECRET_KEY": "change-me-in-production"},
        {"JWT_SECRET_KEY": "replace-with-a-long-random-secret"},
        {"JWT_SECRET_KEY": "dev-only-change-me"},
        {"JWT_SECRET_KEY": "too-short"},
        {"MINIO_ACCESS_KEY": "minioadmin"},
        {"MINIO_SECRET_KEY": "minioadmin"},
        {"DEFAULT_ADMIN_PASSWORD": "Admin@12345"},
        {"CCTV_CREDENTIALS_ENCRYPTION_KEY": ""},
        {"DEBUG": True},
    ],
)
def test_insecure_production_config_is_rejected(override):
    with pytest.raises(ValidationError, match="Refusing to start"):
        _secure(**override)


def test_development_allows_defaults():
    settings = Settings(_env_file=None, ENVIRONMENT="development")
    assert not settings.is_production


def test_invalid_cctv_credentials_encryption_key_is_rejected():
    with pytest.raises(ValidationError, match="CCTV_CREDENTIALS_ENCRYPTION_KEY"):
        Settings(_env_file=None, CCTV_CREDENTIALS_ENCRYPTION_KEY="not-a-key")


def test_minio_endpoint_property_uses_backend_endpoint():
    settings = Settings(
        _env_file=None,
        MINIO_ENDPOINT="http://minio:9000",
    )

    assert settings.minio_endpoint == "http://minio:9000"


def test_mongodb_uri_is_built_from_credentials_and_components():
    settings = Settings(
        _env_file=None,
        MONGODB_HOST="db.example",
        MONGODB_PORT=27018,
        MONGODB_USERNAME="cctv user",
        MONGODB_PASSWORD="p@ss:/",
        MONGODB_AUTH_SOURCE="admin",
        MONGODB_DATABASE="records",
    )

    assert settings.mongodb_uri == (
        "mongodb://cctv+user:p%40ss%3A%2F@db.example:27018/"
        "records?authSource=admin"
    )


def test_mongodb_uri_override_takes_precedence():
    settings = Settings(
        _env_file=None,
        MONGODB_URI="mongodb://external.example:27017/cctv",
        MONGODB_HOST="ignored",
    )

    assert settings.mongodb_uri == "mongodb://external.example:27017/cctv"


def test_partial_mongodb_credentials_are_rejected():
    with pytest.raises(ValidationError, match="must both be set"):
        Settings(_env_file=None, MONGODB_USERNAME="cctv")


def test_jwt_signing_key_requires_a_configured_secret():
    settings = Settings(_env_file=None, JWT_SECRET_KEY="")

    with pytest.raises(RuntimeError, match="JWT_SECRET_KEY"):
        _ = settings.jwt_signing_key


@pytest.mark.parametrize("algorithm", ["none", "RS256", "hs256"])
def test_unsafe_jwt_algorithm_is_rejected(algorithm):
    with pytest.raises(ValidationError, match="JWT_ALGORITHM"):
        Settings(_env_file=None, JWT_ALGORITHM=algorithm)
