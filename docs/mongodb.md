# MongoDB

Database: `MONGODB_DATABASE` (default `cctv_manager`).

## Collections

### `users`
```json
{
  "_id": "ObjectId",
  "username": "admin",
  "email": "admin@example.com",
  "password_hash": "<argon2id>",
  "full_name": "System Administrator",
  "role": "ADMIN",
  "is_active": true,
  "token_version": 1,
  "created_at": "ISODate",
  "updated_at": "ISODate",
  "last_login_at": "ISODate | null"
}
```

### `cctvs`
```json
{
  "_id": "ObjectId",
  "cctv_id": "CCTV-YGN-000001",
  "location": { "type": "Point", "coordinates": [96.1561, 16.8409] },
  "latitude": 16.8409,
  "longitude": 96.1561,
  "region": "Yangon",
  "township": "Bahan",
  "street": "Main St",
  "status": "ACTIVE",
  "description": "...",
  "images": [
    { "id": "uuid", "image_type": "CCTV_VIEW", "object_key": "cctv/.../view/x.jpg",
      "thumbnail_key": null, "file_size": 12345, "mime_type": "image/jpeg",
      "width": 1920, "height": 1080, "created_at": "ISODate" }
  ],
  "created_by": "<user_id>", "updated_by": "<user_id>",
  "created_at": "ISODate", "updated_at": "ISODate"
}
```

### `refresh_tokens`
`{ user_id, token_hash, expires_at, revoked, created_at, user_agent, ip_address }`

### `audit_logs`
`{ user_id, action, resource_type, resource_id, timestamp, ip_address, metadata }`

## Indexes

Created automatically by `app.db.mongo.init_indexes()` (run via
`python -m app.bootstrap`):

| Collection | Index | Type |
|-----------|-------|------|
| users | `username` | unique |
| users | `email` | unique |
| users | `role`, `is_active` | |
| cctvs | `cctv_id` | unique |
| cctvs | `location` | **2dsphere** |
| cctvs | `status`, `region`, `township`, `created_at`, `created_by` | |
| refresh_tokens | `token_hash`, `user_id`, TTL `expires_at` | |
| audit_logs | `user_id`, `action`, `resource_id`, `timestamp` | |

## Geospatial queries

- **Viewport:** `$geoWithin` a `$geometry` polygon built from map bounds.
- **Nearby:** `$near` with `$maxDistance`.

Both rely on the `2dsphere` index, so they scale to large collections without
client-side filtering.

## Alternative: Atlas/`motor`

The access layer is intentionally synchronous PyMongo (`pymongo`), which is
straightforward and fast for this workload (FastAPI runs sync endpoints in a
threadpool). To move to async, swap `app/db/mongo.py` for `motor` and make
service functions `async`; the query shapes stay identical.
