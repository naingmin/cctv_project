"""Application configuration loaded from environment variables."""
import base64
from functools import lru_cache
from pathlib import Path
from typing import List
from urllib.parse import quote_plus, urlsplit

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_INFRASTRUCTURE_ENV_FILE = (
    Path(__file__).resolve().parents[2] / "infrastructure" / ".env"
)

# Placeholder/default values shipped in code, .env.example and
# docker-compose.yml. Any of these in production means secrets were never set.
_INSECURE_JWT_SECRETS = {
    "",
    "change-me-in-production",
    "replace-with-a-long-random-secret",
    "dev-only-change-me",
}
_INSECURE_MINIO_CREDENTIALS = {"", "minioadmin"}
_INSECURE_ADMIN_PASSWORDS = {"", "Admin@12345", "SET_A_UNIQUE_ADMIN_PASSWORD_HERE"}
_MIN_JWT_SECRET_LENGTH = 32
_ALLOWED_JWT_ALGORITHMS = {"HS256", "HS384", "HS512"}


class Settings(BaseSettings):
    """Central application settings.

    All values are read from environment variables (or a local ``.env`` file).
    Never hardcode secrets here.
    """

    model_config = SettingsConfigDict(
        env_file=_INFRASTRUCTURE_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=True,
    )

    # --- App ---
    APP_NAME: str = "CCTV Data Collection & Management System"
    API_V1_PREFIX: str = "/api/v1"
    ENVIRONMENT: str = "development"
    DEBUG: bool = False

    # --- MongoDB ---
    # Set MONGODB_URI to use a complete connection string, or set the
    # individual host/port/credential fields below.
    MONGODB_URI: str = ""
    MONGODB_HOST: str = "localhost"
    MONGODB_PORT: int = Field(default=27017, ge=1, le=65535)
    MONGODB_USERNAME: str = ""
    MONGODB_PASSWORD: str = ""
    MONGODB_AUTH_SOURCE: str = "admin"
    MONGODB_DATABASE: str = "cctv_manager"

    # --- JWT ---
    JWT_SECRET_KEY: str = ""
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30
    # URL-safe base64 encoding of a random 32-byte AES-256 key.
    CCTV_CREDENTIALS_ENCRYPTION_KEY: str = ""

    # --- Keycloak Integration ---
    # When these are set, FastAPI will validate Keycloak-issued access tokens
    # instead of legacy username/password tokens.
    KEYCLOAK_ISSUER: str = ""  # e.g. https://auth.example.com/realms/cctv-realm
    KEYCLOOK_CLIENT_ID: str = ""  # The Keycloak client ID

    # --- Object storage (MinIO / S3-compatible) ---
    # Endpoint the *backend* uses for S3 calls. Inside Docker this is the
    # service name, e.g. http://minio:9000.
    MINIO_ENDPOINT: str = "http://localhost:9000"
    # Endpoint embedded in presigned URLs, i.e. the one *clients* can reach.
    # Must be the browser/phone-visible host, e.g. http://localhost:9000.
    # Falls back to MINIO_ENDPOINT when unset.
    MINIO_PUBLIC_ENDPOINT: str = ""
    MINIO_ACCESS_KEY: str = ""
    MINIO_SECRET_KEY: str = ""
    MINIO_BUCKET: str = "cctv-media"
    MINIO_REGION: str = "us-east-1"
    MINIO_USE_SSL: bool = False
    PRESIGN_EXPIRE_SECONDS: int = 300
    MAX_IMAGE_SIZE_MB: int = 10

    # --- CORS ---
    CORS_ORIGINS: List[str] = Field(default_factory=list)
    # Regex alternative to CORS_ORIGINS, for dev servers on random ports
    # (e.g. `flutter run -d chrome` picks a new port each run).
    # Ignored in production - see `cors_origin_regex`.
    CORS_ORIGIN_REGEX: str = ""

    # --- Map ---
    MAP_TILE_URL: str = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    MAP_ATTRIBUTION: str = "&copy; OpenStreetMap contributors"

    # --- Pagination ---
    DEFAULT_PAGE_SIZE: int = 20
    MAX_PAGE_SIZE: int = 100

    # --- Default admin (seed only; change password after first login) ---
    DEFAULT_ADMIN_USERNAME: str = "admin"
    DEFAULT_ADMIN_EMAIL: str = "admin@example.com"
    DEFAULT_ADMIN_PASSWORD: str = ""
    DEFAULT_ADMIN_FULL_NAME: str = "System Administrator"

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def _split_origins(cls, value):
        if value is None or value == "":
            return []
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @field_validator("JWT_ALGORITHM")
    @classmethod
    def _check_jwt_algorithm(cls, value: str) -> str:
        # Never let configuration select "none" or an asymmetric algorithm
        # that would be verified with the shared HMAC secret.
        if value not in _ALLOWED_JWT_ALGORITHMS:
            raise ValueError(
                f"JWT_ALGORITHM must be one of {sorted(_ALLOWED_JWT_ALGORITHMS)}."
            )
        return value

    @field_validator("CCTV_CREDENTIALS_ENCRYPTION_KEY")
    @classmethod
    def _check_cctv_credentials_encryption_key(cls, value: str) -> str:
        if not value:
            return value
        try:
            decoded = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
        except Exception as exc:
            raise ValueError(
                "CCTV_CREDENTIALS_ENCRYPTION_KEY must be URL-safe base64 "
                "encoding of 32 bytes."
            ) from exc
        if len(decoded) != 32:
            raise ValueError(
                "CCTV_CREDENTIALS_ENCRYPTION_KEY must decode to exactly 32 bytes."
            )
        return value

    @model_validator(mode="after")
    def _refuse_insecure_production(self) -> "Settings":
        """Fail fast instead of serving production with known secrets."""
        if not self.MONGODB_URI and bool(self.MONGODB_USERNAME) != bool(
            self.MONGODB_PASSWORD
        ):
            raise ValueError(
                "MONGODB_USERNAME and MONGODB_PASSWORD must both be set or both be empty."
            )

        if not self.is_production:
            return self
        problems = []
        if (
            self.JWT_SECRET_KEY in _INSECURE_JWT_SECRETS
            or len(self.JWT_SECRET_KEY) < _MIN_JWT_SECRET_LENGTH
        ):
            problems.append(
                f"JWT_SECRET_KEY must be a random value of at least "
                f"{_MIN_JWT_SECRET_LENGTH} characters"
            )
        if (
            self.MINIO_ACCESS_KEY in _INSECURE_MINIO_CREDENTIALS
            or self.MINIO_SECRET_KEY in _INSECURE_MINIO_CREDENTIALS
        ):
            problems.append("MINIO_ACCESS_KEY / MINIO_SECRET_KEY use the default")
        if self.DEFAULT_ADMIN_PASSWORD in _INSECURE_ADMIN_PASSWORDS:
            problems.append("DEFAULT_ADMIN_PASSWORD uses the default")
        if self.MONGODB_URI:
            parsed_mongodb_uri = urlsplit(self.MONGODB_URI)
            mongodb_has_credentials = (
                parsed_mongodb_uri.username is not None
                and parsed_mongodb_uri.password is not None
            )
        else:
            mongodb_has_credentials = bool(
                self.MONGODB_USERNAME and self.MONGODB_PASSWORD
            )
        if not mongodb_has_credentials:
            problems.append("MongoDB authentication credentials are not set")
        if not self.CCTV_CREDENTIALS_ENCRYPTION_KEY:
            problems.append("CCTV_CREDENTIALS_ENCRYPTION_KEY is not set")
        if self.DEBUG:
            problems.append("DEBUG must be false")
        if problems:
            raise ValueError(
                "Refusing to start with ENVIRONMENT=production: "
                + "; ".join(problems)
                + "."
            )
        return self

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.lower() in {"production", "prod"}

    @property
    def cors_origin_regex(self) -> str | None:
        """Regex allow-list, or None.

        Empty in production so a permissive dev regex can never widen the
        allow-list on a real deployment.
        """
        if self.is_production:
            return None
        return self.CORS_ORIGIN_REGEX or None

    @property
    def max_image_bytes(self) -> int:
        return self.MAX_IMAGE_SIZE_MB * 1024 * 1024

    @property
    def minio_endpoint(self) -> str:
        """Endpoint the backend uses for S3 operations."""
        return self.MINIO_ENDPOINT

    @property
    def jwt_signing_key(self) -> str:
        """Return a configured, non-placeholder key for signing legacy JWTs."""
        if (
            self.JWT_SECRET_KEY in _INSECURE_JWT_SECRETS
            or len(self.JWT_SECRET_KEY) < _MIN_JWT_SECRET_LENGTH
        ):
            raise RuntimeError(
                "Set JWT_SECRET_KEY to a random value of at least "
                f"{_MIN_JWT_SECRET_LENGTH} characters in infrastructure/.env."
            )
        return self.JWT_SECRET_KEY

    @property
    def mongodb_uri(self) -> str:
        """Return the explicit MongoDB URI or build one from its components."""
        if self.MONGODB_URI:
            return self.MONGODB_URI

        credentials = ""
        if self.MONGODB_USERNAME and self.MONGODB_PASSWORD:
            credentials = (
                f"{quote_plus(self.MONGODB_USERNAME)}:"
                f"{quote_plus(self.MONGODB_PASSWORD)}@"
            )
        auth_source = (
            f"?authSource={quote_plus(self.MONGODB_AUTH_SOURCE)}"
            if credentials
            else ""
        )
        return (
            f"mongodb://{credentials}{self.MONGODB_HOST}:{self.MONGODB_PORT}/"
            f"{self.MONGODB_DATABASE}{auth_source}"
        )

    @property
    def minio_public_endpoint(self) -> str:
        """Endpoint to embed in presigned URLs.

        Presigned URLs are fetched by the client, not by this process, so they
        must point at an address the client can resolve. Inside Docker the
        backend reaches MinIO as ``http://minio:9000`` while the browser needs
        ``http://localhost:9000``; ``MINIO_PUBLIC_ENDPOINT`` bridges that.
        """
        return self.MINIO_PUBLIC_ENDPOINT or self.MINIO_ENDPOINT


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
