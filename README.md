# CCTV Data Collection & Management System

A production-oriented, geospatial CCTV data collection and management platform.

- **Mobile:** Flutter (Dart, Riverpod, flutter_map, OpenStreetMap)
- **Backend:** FastAPI (Python), JWT auth, Argon2id, RBAC
- **Database:** MongoDB (GeoJSON + `2dsphere`)
- **Object storage:** MinIO (private bucket, presigned URLs)

## Repository layout

```
Project/
├── backend/            # FastAPI application (+ tests)
├── infrastructure/     # Docker Compose (MongoDB, MinIO, backend)
├── docs/               # architecture, api, auth, mongodb, minio, map, security, deployment
├── lib/                # Flutter app (this directory is the mobile project root)
└── README.md
```

## Quick start (full stack)

```bash
# 1. Backend + MongoDB + MinIO
docker compose -f infrastructure/docker-compose.yml up -d --build
#    API:     http://localhost:8000
#    Docs:    http://localhost:8000/docs
#    MinIO:   http://localhost:9000  (S3 API, used for presigned URLs)
#    Console: http://localhost:9001  (credentials: infrastructure/.env)

# 2. Flutter app
flutter pub get
flutter run
```

A default admin is created only when the database is empty, using
`DEFAULT_ADMIN_USERNAME` / `DEFAULT_ADMIN_PASSWORD` from `backend/.env`.
Change its password immediately:

```bash
cd backend
python -m scripts.set_password admin
```

With `ENVIRONMENT=production` the backend refuses to start while any default
or placeholder secret (JWT key, MinIO keys, admin seed password) or `DEBUG=true`
is still configured.

## Backend development

```bash
cd backend
python -m venv .venv
. .venv/bin/activate            # Windows: .venv\Scripts\activate
pip install -r requirements.txt -r requirements-dev.txt
cp .env.example .env            # edit values
python -m app.bootstrap         # ensure indexes + default admin
uvicorn app.main:app --reload

# Tests
pytest
```

## Flutter development

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Configure the API base URL for the app (see `lib/core/config/app_config.dart`).

## Environment variables

See `backend/.env.example` for the full list. Key groups: app/env, MongoDB,
JWT, MinIO, CORS, map tiles, default admin seed.

Never commit real secrets; `.env` is git-ignored.

## Security

See [docs/security.md](docs/security.md). Highlights: Argon2id passwords, hashed
+ rotated refresh tokens, server-side RBAC, private object storage with
short-lived presigned URLs, rate limiting, restricted CORS, and audit logging.

## Documentation

- [Architecture](docs/architecture.md)
- [API](docs/api.md)
- [Authentication](docs/authentication.md)
- [MongoDB](docs/mongodb.md)
- [MinIO](docs/minio.md)
- [Map](docs/map.md)
- [Security](docs/security.md)
- [Deployment](docs/deployment.md)

## Status

The **backend is implemented and tested** (103 passing tests covering auth,
RBAC with region-scoped roles, CCTV CRUD/search/filter/pagination/geospatial,
uploads authorization, area suggestions, user management, and audit logging).

The **Flutter client** uses the REST API:
- JWT authentication with refresh-token rotation and secure storage
- Role-based UI for all four roles (Administrator, Regional Admin, Supervisor,
  Viewer), with region/township assignment when creating or editing users
- Presigned image upload flow (MinIO), on Android, iOS, desktop and web
- Viewport-based map loading with the new API
- Real-time stats from MongoDB aggregation
- 103 passing Flutter tests

**Release builds** (`flutter build apk --release`) require `android/key.properties`
plus the `.jks` keystore (the build fails with instructions if they are missing),
use `targetSdk 35`, and refuse plain `http://` server addresses unless
`cctv.allowHttpInRelease=true` is deliberately set in `android/gradle.properties`.
