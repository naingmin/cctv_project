"""Shared pytest fixtures using mongomock and in-memory overrides."""
from __future__ import annotations

import mongomock
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.api.deps import get_db
from app.core.rbac import Role
from app.core.rate_limit import reset_limiters
from app.main import create_app
from app.schemas.user import UserCreate
from app.services import user_service

# Auth tests must not depend on developer or deployment secrets.
if len(settings.JWT_SECRET_KEY) < 32:
    settings.JWT_SECRET_KEY = "test-only-" + "x" * 48

ADMIN = {"username": "admin", "password": "Admin@12345"}
USER = {"username": "viewer", "password": "Viewer@12345"}


@pytest.fixture(autouse=True)
def _reset_rate_limiters():
    reset_limiters()
    yield
    reset_limiters()


@pytest.fixture()
def db():
    client = mongomock.MongoClient()
    database = client["test_cctv"]
    # mongomock supports unique/2dsphere index creation (2dsphere is a no-op).
    database.users.create_index("username", unique=True)
    database.users.create_index("email", unique=True)
    database.cctvs.create_index("cctv_id", unique=True)
    database.cctvs.create_index([("location", "2dsphere")])
    return database


@pytest.fixture()
def app(db):
    application = create_app()
    application.dependency_overrides[get_db] = lambda: db
    return application


@pytest.fixture()
def client(app):
    return TestClient(app)


@pytest.fixture()
def admin_user(db):
    return user_service.create_user(
        db,
        UserCreate(
            username=ADMIN["username"],
            email="admin@example.com",
            full_name="Admin",
            role=Role.ADMIN,
            is_active=True,
            password=ADMIN["password"],
        ),
    )


@pytest.fixture()
def normal_user(db):
    return user_service.create_user(
        db,
        UserCreate(
            username=USER["username"],
            email="viewer@example.com",
            full_name="Viewer",
            role=Role.USER,
            is_active=True,
            password=USER["password"],
        ),
    )


def _login(client, creds):
    resp = client.post("/api/v1/auth/login", json=creds)
    assert resp.status_code == 200, resp.text
    return resp.json()["data"]["access_token"]


@pytest.fixture()
def admin_token(client, admin_user):
    return _login(client, ADMIN)


@pytest.fixture()
def user_token(client, normal_user):
    return _login(client, USER)


def auth(token):
    return {"Authorization": f"Bearer {token}"}
