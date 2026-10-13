# Security

This document describes the security controls actually implemented.

## Authentication

- JWT access tokens (HS256), short-lived (15 min), signed with an externalized
  `JWT_SECRET_KEY`.
- Opaque 384-bit refresh tokens, stored as a SHA-256 hash (unique index, one
  lookup per refresh), revocable, with TTL expiry.
- Rotation is atomic: the old token is revoked with a conditional update, so
  two concurrent refreshes with the same token cannot both succeed.
- Reuse detection: presenting an already-rotated token revokes **every**
  session of that user (a replayed token implies it was copied).
- `token_version` claim embedded in access tokens; bumping it invalidates all
  sessions for a user (on role, status, region/township, or password change).
- Role and region are read from the database on every request, never from
  token claims.
- Passwords hashed with Argon2id. Plaintext is never stored or logged.
- CCTV IP addresses, usernames, and passwords are encrypted in MongoDB with
  AES-256-GCM using `CCTV_CREDENTIALS_ENCRYPTION_KEY`. The key must be kept
  outside the database, stable across restarts, and backed up securely.

## Authorization (RBAC + geographic scope)

Role permissions live in `app/core/rbac.py`; *which records* a user may see is
defined once in `cctv_service.scope_filter` and applied to every read path
(list, map, nearby, stats, detail) and every write.

| Role (stored value) | CCTV/data scope | CCTV permissions | User management | Audit logs |
|---------------------|-----------------|------------------|-----------------|------------|
| `ADMIN` / `OVERALL_ADMIN` | All regions and sub-regions | Full CRUD and image management | All users and roles | All logs |
| `REGIONAL_ADMIN` | Assigned region only | Full CRUD and image management | Supervisors/operators in region | Region only |
| `SUPERVISOR` | Assigned region and sub-region only | Full CRUD and image management | Operators in sub-region | Sub-region only |
| `USER` / `OPERATOR` | CCTV records where `created_by` is the current user | Full CRUD and image management on owned records | None | Owned CCTV only |

- **Deny by default:** a regional admin or supervisor without an assigned area
  gets `403`, never global access. The API refuses to save such accounts.
- Client filters are ANDed with the scope: they can narrow a view, never widen it.
- Scoped queries are applied before returning records; out-of-scope direct IDs
  return `404` to avoid disclosing whether a CCTV or user exists.
- A scoped user cannot create a record outside their area or move one out of
  it (including clearing its region). Operators are bound to their creator ID.
- Regional administrators cannot create or promote users into administrator
  roles; supervisors can manage only operators in their own sub-region.
- Nobody can change their own role or disable or delete their own account; the
  last active system administrator cannot be demoted, disabled, or deleted.
- `region_id` / `sub_region_id` are used when assigned. Existing deployments
  without ID-based geography continue to use `region` / `township`; ID-tagged
  records are not visible through legacy name-only scopes.
- Search text is regex-escaped (literal match only).
- Tested in `tests/test_rbac.py` and `tests/test_access_control.py`.
- Hiding UI is **not** treated as security.

## Input validation

- Pydantic validates all request bodies and query params server-side.
- Latitude ∈ [-90, 90], longitude ∈ [-180, 180].
- CCTV ID normalized to uppercase, unique (409 on duplicate).
- Image MIME/extension allow-list and max size.
- Pagination bounded (max 100).

## Object storage

- MinIO bucket is private.
- Presigned PUT/GET URLs are short-lived (`PRESIGN_EXPIRE_SECONDS`, default 300).
- Object keys are server-generated UUIDs; client filenames are never used.
- Image completion verifies the object key prefix matches the CCTV, preventing
  cross-record writes.
- Image download checks `cctv.read` and ownership before signing a URL.
- MinIO credentials exist only in the backend environment.

## Rate limiting

`/auth/login`, `/auth/refresh`, and `/auth/change-password` are rate limited per
client IP (token bucket) to blunt brute-force and credential stuffing.

## Transport & CORS

- HTTPS is required in production (terminate TLS at the proxy).
- CORS uses explicit origins from `CORS_ORIGINS`; `*` is not used in production.
- Production disables interactive API docs.

## Error handling

Centralized handlers return consistent, safe error bodies. Internal exceptions
never leak stack traces to clients (logged server-side only).

## Audit logging

Successful CCTV create, update, delete, detail-view, image-add, and image-delete
actions are recorded with actor ID/name/role, CCTV ID/name, region and
sub-region IDs, UTC timestamp, IP address, request method/path/user-agent, and
non-sensitive metadata. `GET /api/v1/audit-logs` enforces the same geographic
or creator scope as CCTV access. Audit database failures are returned as
request failures rather than silently reported as success. Passwords, hashes,
tokens, and secrets are never logged.

## Secret management

All secrets come from environment variables. `.env` is git-ignored; only
`.env.example` is committed. No secret is bundled into the Flutter app.
Production requires `CCTV_CREDENTIALS_ENCRYPTION_KEY`; generate it with
`python -c "import secrets; print(secrets.token_urlsafe(32))"`. CCTV credentials
are returned only by the scoped, authenticated single-record detail endpoint,
never by list, map, nearby, audit, or marker responses.
