# MinIO Object Storage

MinIO provides S3-compatible private object storage for CCTV images. MongoDB
stores only **metadata** (object keys, sizes, dimensions); binaries live in MinIO.

## Configuration

```
MINIO_ENDPOINT=http://minio:9000
MINIO_ACCESS_KEY=<access key from infrastructure/.env>
MINIO_SECRET_KEY=<secret key from infrastructure/.env>
MINIO_BUCKET=cctv-media
MINIO_REGION=us-east-1
MINIO_USE_SSL=false
MINIO_PUBLIC_ENDPOINT=http://localhost:9000
PRESIGN_EXPIRE_SECONDS=300
```

> **Important:** MinIO credentials live only in the backend environment. They are
> never bundled into the Flutter app or committed to Git. Flutter only ever
> receives short-lived presigned URLs.

`MINIO_ENDPOINT` and `MINIO_PUBLIC_ENDPOINT` must include the `http://` or
`https://` scheme. They are deliberately **separate**:

| Setting | Used for | In Docker |
| --- | --- | --- |
| `MINIO_ENDPOINT` | the backend's own S3 calls (head, delete, ensure-bucket) | `http://minio:9000` |
| `MINIO_PUBLIC_ENDPOINT` | the host baked into presigned URLs | Must be reachable by the Flutter client |

Inside Docker the backend reaches MinIO as `http://minio:9000`, but a client
outside Docker cannot resolve that name. `http://localhost:9000` is suitable
only for a client running on the same computer as MinIO. On Android,
`localhost` means the Android device itself, not the computer hosting MinIO.
Set `MINIO_PUBLIC_ENDPOINT` to an address the device can reach:

| Flutter client | Example `MINIO_PUBLIC_ENDPOINT` |
| --- | --- |
| Android emulator | `http://10.0.2.2:9000` |
| Physical Android device on the same Wi-Fi | `http://<computer-LAN-IP>:9000`, e.g. `http://192.168.1.20:9000` |
| Flutter web or desktop on the MinIO host | `http://localhost:9000` |

For the mixed local setup (MinIO in Docker, backend running natively), set
`MINIO_PUBLIC_ENDPOINT` in `backend/.env` and restart the backend. If the
backend is also running in Docker, set it in `infrastructure/.env` and
recreate the backend container. For a physical device, allow inbound access to
port 9000 through the host firewall. `MINIO_PUBLIC_ENDPOINT` defaults to
`MINIO_ENDPOINT` when unset, which is only correct when both live on the same
network.

Rewriting a presigned URL's host invalidates its signature, so in production
point `MINIO_PUBLIC_ENDPOINT` at the address clients actually use (a reverse
proxy or `MINIO_SERVER_URL`) rather than rewriting URLs in code.

### Browser uploads and CORS

Flutter web `PUT`s image bytes straight to MinIO, so the browser sends a CORS
preflight. Set `MINIO_API_CORS_ALLOW_ORIGIN` on the MinIO service to the app's
origin(s) — `docker-compose.yml` defaults it to `http://localhost:*`, which must
be narrowed in production. Keep it in sync with the API's `CORS_ORIGIN_REGEX`.

## Bucket layout

Private bucket `cctv-media`:

```
cctv/{cctv_id}/view/{uuid}.jpg
cctv/{cctv_id}/environment/{uuid}.jpg
cctv/{cctv_id}/thumbnails/{uuid}.jpg
```

Object keys are **server-generated UUIDs** — raw client filenames are never used
as keys.

## Upload flow (presigned PUT)

1. Client → `POST /api/v1/uploads/presign` (ADMIN only).
2. Backend validates CCTV existence, MIME type, and extension; generates a safe
   object key and a short-lived presigned PUT URL. The declared `content_type`
   is **signed into the request**, so MinIO rejects an upload whose
   `Content-Type` differs from the one declared here.
3. Client `PUT`s the bytes directly to MinIO (the file does not stream through
   FastAPI).
4. Client → `POST /api/v1/cctvs/{id}/images/complete`. Backend verifies the
   object exists, reads its **real** size from storage (the client's claim is
   not trusted), enforces `MAX_IMAGE_SIZE_MB` and deletes the object if it is
   oversized, then records metadata in MongoDB.

## Download flow (presigned GET)

`GET /api/v1/cctvs/{id}/images/{image_id}/url` authenticates the caller, checks
`cctv.read`, confirms the image belongs to that CCTV, then returns a short-lived
presigned GET URL. No permanent public URLs are ever exposed.

`GET /api/v1/cctvs/{id}/images/urls` returns a `{image_id: url}` map for every
image on the record in a single round trip, so a gallery costs one call rather
than one per thumbnail.

List and detail responses additionally carry `view_image_url`: a presigned GET
for the record's primary `CCTV_VIEW` image. It is signed per response and never
persisted, because it expires.

## Validation

- Allowed MIME: `image/jpeg`, `image/png`, `image/webp`.
- Allowed extensions: `.jpg`, `.jpeg`, `.png`, `.webp`.
- SVG, archives, and unknown binaries are rejected.
- Max size: `MAX_IMAGE_SIZE_MB` (default 10 MB), enforced at completion time
  against the object's real size.

> **Note:** because bytes go straight to storage, a presigned `PUT` cannot carry
> a size limit — S3 only supports `content-length-range` on presigned **POST**
> policies. Oversized objects are therefore rejected and deleted at completion
> rather than blocked before upload. Enforcing a pre-upload cap would mean
> switching the client to a presigned POST policy.

## Thumbnails

`build_thumbnail_key()` exists and the schema stores `thumbnail_key`, but
thumbnail generation is not implemented: presign returns `thumbnail_key: null`.
Both delete paths already clean up a thumbnail when one is present.

## Local setup

```bash
docker compose -f infrastructure/docker-compose.yml up -d minio
# API:     http://localhost:9000
# Console: http://localhost:9001  (credentials: infrastructure/.env)
```

The bucket is created automatically by `python -m app.bootstrap`.
