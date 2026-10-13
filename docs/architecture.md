# Architecture

## Overview

The system is a three-tier geospatial CCTV management platform:

```
Flutter (Dart / Riverpod / flutter_map)
        │  HTTPS / REST (JWT Bearer)
        ▼
FastAPI (Python)  ──► MongoDB (metadata, GeoJSON, audit)
        │
        └────────────► MinIO (image objects, presigned URLs)
```

- **Flutter** renders the UI, captures GPS/camera input, and talks only to FastAPI.
- **FastAPI** owns authentication, authorization, validation, business logic, and
  all access to MongoDB and MinIO. No secrets ever reach the client.
- **MongoDB** stores users, CCTV metadata (with a GeoJSON `Point` + `2dsphere`
  index), refresh-token hashes, and audit logs.
- **MinIO** stores image binaries in a private bucket. Clients upload/download
  via short-lived presigned URLs.

## Backend layering

```
app/
  config.py            # environment-driven settings
  main.py              # app factory, middleware, error handlers
  core/                # security, rbac, errors, rate limiting, logging
  db/mongo.py          # connection + index management
  schemas/             # Pydantic request/response models
  services/            # business logic (users, cctv, tokens, storage, audit)
  api/deps.py          # auth + permission dependencies
  api/v1/              # routers (auth, cctv, uploads, users, audit)
```

Routers are thin; all logic lives in services so it can be unit-tested without
HTTP.

## Geospatial model

Every CCTV document stores a GeoJSON Point:

```json
"location": { "type": "Point", "coordinates": [longitude, latitude] }
```

> GeoJSON order is **[longitude, latitude]**. This is the opposite of the
> human-friendly lat/lng ordering and is the single most common source of bugs
> in GIS apps. The service converts safely in `to_geojson()`.

A `2dsphere` index powers viewport (`$geoWithin`) and nearby (`$near`) queries,
so no geographic filtering happens on the client and the full dataset is never
sent to Flutter.

## Scalability

- Viewport map queries return only lightweight markers in the visible bounds.
- Marker clustering is applied client-side on the already-bounded result set.
- Pagination is enforced at the API (default 20, max 100).
- Statistics use MongoDB aggregation, never full scans to the client.
