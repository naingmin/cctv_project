# API Reference

Base URL: `{HOST}/api/v1`

All responses use a consistent envelope:

```json
// success
{ "success": true, "data": { ... }, "message": "OK" }

// error
{ "success": false, "error": { "code": "FORBIDDEN", "message": "..." } }
```

Authenticated endpoints require `Authorization: Bearer <access_token>`.

## Authentication

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/login` | public | Login with username/email + password |
| POST | `/auth/refresh` | public | Rotate refresh token, issue new access token |
| POST | `/auth/logout` | user | Revoke a refresh token |
| GET | `/auth/me` | user | Current user + permissions |
| POST | `/auth/change-password` | user | Change password (invalidates sessions) |

`POST /auth/login`
```json
{ "username": "admin", "password": "<your password>" }
```
→ `200`
```json
{ "success": true, "data": {
  "access_token": "...", "refresh_token": "...",
  "token_type": "bearer", "expires_in": 900 }, "message": "Login successful." }
```

## CCTV

| Method | Path | Permission |
|--------|------|-----------|
| GET | `/cctvs` | `cctv.read` |
| GET | `/cctvs/{id}` | `cctv.read` |
| GET | `/cctvs/map` | `cctv.read` |
| GET | `/cctvs/nearby` | `cctv.read` |
| GET | `/cctvs/stats` | `cctv.read` |
| POST | `/cctvs` | `cctv.create` |
| PUT | `/cctvs/{id}` | `cctv.update` |
| DELETE | `/cctvs/{id}` | `cctv.delete` |

**List query params:** `page`, `limit` (≤100), `search`, `status`
(`ACTIVE|INACTIVE|MAINTENANCE`), `region`, `township`, `tag`
(`ALPRS|FRS|CPCS|ARDS`), `date_from`, `date_to`. Tag filtering returns records
containing the selected tag and can be combined with the other filters.

**Map viewport:** `?min_lat=&max_lat=&min_lng=&max_lng=&zoom=&status=`
Returns lightweight markers only.

**Nearby:** `?latitude=&longitude=&radius_meters=` (uses MongoDB `$near`).

**CCTV record fields:** `direction` is one of `N`, `NE`, `E`, `SE`, `S`,
`SW`, `W`, or `NW`; `description` is optional. `ip_address` must be a valid
IPv4 or IPv6 address. Optional `username` and `password` hold stream access
credentials. `tags` is an array containing any unique combination of `ALPRS`,
`FRS`, `CPCS`, and `ARDS`.

Credentials are encrypted at rest using the backend-only
`CCTV_CREDENTIALS_ENCRYPTION_KEY`. The scoped `GET /cctvs/{id}` detail endpoint
returns them to authenticated users with `cctv.read`; list, map, nearby, and
marker payloads do not contain them.

**Stats:** total/active/inactive/maintenance counts, added today/this month,
user counts (aggregation-based).

## Uploads & Images

| Method | Path | Permission |
|--------|------|-----------|
| POST | `/uploads/presign` | `cctv.image.upload` |
| POST | `/cctvs/{id}/images/complete` | `cctv.image.upload` |
| GET | `/cctvs/{id}/images/{image_id}/url` | `cctv.read` |
| GET | `/cctvs/{id}/images/urls` | `cctv.read` |
| DELETE | `/cctvs/{id}/images/{image_id}` | `cctv.image.delete` |

**Upload flow**

1. `POST /uploads/presign` with `{ cctv_id, image_type, filename, content_type }`
   → `{ upload_url, object_key, thumbnail_key, expires_in }`. `upload_url` is an
   **absolute** presigned URL; `content_type` is signed into it.
2. Client `PUT`s the bytes directly to `upload_url` (MinIO), sending exactly the
   `Content-Type` declared in step 1.
3. `POST /cctvs/{id}/images/complete` with the `object_key` + metadata.
4. FastAPI verifies the object exists, reads its real size and MIME from storage,
   enforces the size cap (deleting the object if oversized), and stores metadata
   in MongoDB. Client-supplied `file_size` is recorded only as a fallback.

Image access is authorized: `GET .../url` returns a short-lived presigned GET
URL only if the caller has `cctv.read` and the image belongs to the CCTV.
`GET /cctvs/{id}/images/urls` returns `{ urls: {image_id: url}, expires_in }` for
every image on the record in one call.

List and detail payloads also include `view_image_url`, a presigned GET for the
record's primary `CCTV_VIEW` image (map markers expose it as `thumbnail_url`).
It is signed per response and never persisted, because it expires.

## Users (Role-scoped)

| Method | Path | Permission |
|--------|------|-----------|
| GET | `/users` | `user.read` |
| POST | `/users` | `user.create` |
| GET | `/users/{id}` | `user.read` |
| PUT | `/users/{id}` | `user.update` |
| DELETE | `/users/{id}` | `user.delete` |

System admins may manage all users. Regional admins may manage supervisors
and operators in their region; supervisors may manage operators in their
sub-region. Operators cannot manage users. All user queries are scope-filtered.

User payloads accept `region_id` / `sub_region_id`; legacy deployments may
continue using `region` / `township`. The server uses IDs when assigned and
does not let clients broaden the actor's scope.

Protections: cannot demote/disable/delete the last active system admin, cannot
delete self, and cannot change own role.

## Audit Logs (Scoped)

`GET /audit-logs?page=&limit=&action=&user_id=&resource_id=` — requires
`audit.read`. Results are global for system admins, region-scoped for regional
admins, sub-region-scoped for supervisors, and limited to the operator's own
CCTVs. CCTV audit actions include `CREATE_CCTV`, `UPDATE_CCTV`, `DELETE_CCTV`,
`VIEW_CCTV`, `CREATE_CCTV_IMAGE`, and `DELETE_CCTV_IMAGE`; entries include
actor identity/role, CCTV identity, scope, timestamp, IP, and request details.

## Status Codes

`200` `201` `204` `400` `401` `403` `404` `409` `422` `429` `500`.

## Interactive docs

Swagger UI at `/docs` and ReDoc at `/redoc` (development only).
