# Deployment

## Local development

1. Copy `infrastructure/.env.example` to `infrastructure/.env`.
   If `infrastructure/.env` already exists, merge in missing entries instead
   of overwriting its existing credentials.
2. Fill in the MongoDB username/password, a unique default admin password,
   and a randomly generated `JWT_SECRET_KEY`:

   ```bash
   python -c "import secrets; print(secrets.token_urlsafe(64))"
   ```

3. Generate `CCTV_CREDENTIALS_ENCRYPTION_KEY` from 32 random bytes and keep it
   stable. Losing it makes previously encrypted CCTV credentials unreadable:

   ```bash
   python -c "import secrets; print(secrets.token_urlsafe(32))"
   ```

Compose reads `infrastructure/.env` for variable substitution. The backend
also resolves that same file by path, so native runs do not depend on the
current working directory. Do not commit the file or paste its contents into
logs or support requests.

When running FastAPI natively, start MediaMTX with
`docker compose -f infrastructure/docker-compose.yml up -d mediamtx`; the
control API is available only on host loopback at `http://localhost:9997`.
The default WHEP/HLS URLs are for local clients. Set the public WebRTC host and
playback URLs in `infrastructure/.env` for phones or remote clients.

```bash
# 1. Start Mongo, object storage, MediaMTX, and the API
docker compose -f infrastructure/docker-compose.yml up -d --build

# 2. API is at http://localhost:8000  (docs at /docs)
# 3. MediaMTX uses RTSP :8554, WHEP/WebRTC :8889, HLS :8888, and ICE
#    :8189/udp + :8189/tcp. Its control API (:9997) is internal to Compose.
# 4. Default admin (created only if the DB is empty):
#    admin / DEFAULT_ADMIN_PASSWORD   <-- change immediately:
#    python -m scripts.set_password admin
```

To run the backend directly (without Docker):

```bash
cd backend
python -m venv .venv && . .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python -m app.bootstrap                             # indexes + default admin
uvicorn app.main:app --reload
```

## Production checklist

- [ ] Set `ENVIRONMENT=production` (disables `/docs`, `/redoc`, `/openapi.json`).
- [ ] Use a long random `JWT_SECRET_KEY`
      (`python -c "import secrets; print(secrets.token_urlsafe(64))"`).
- [ ] Set `MONGODB_URI` to a secured/authenticated cluster, or configure
      `MONGODB_HOST`, `MONGODB_PORT`, `MONGODB_USERNAME`, and
      `MONGODB_PASSWORD`.
- [ ] Supply `DEFAULT_ADMIN_PASSWORD` only for initial seeding; rotate it after
      first login and avoid reusing it elsewhere.
- [ ] Back up `CCTV_CREDENTIALS_ENCRYPTION_KEY` securely and keep it unchanged
      while encrypted CCTV credentials must remain readable.
- [ ] Set strong, unique MinIO credentials; keep the bucket private.
- [ ] Serve everything over **HTTPS** (TLS at a reverse proxy / load balancer).
- [ ] Set `CORS_ORIGINS` to the exact allowed origins — never `*`.
- [ ] Restrict rate limiting to a shared store (Redis) if running >1 replica.
- [ ] Rotate the default admin password; disable/remove unused seed accounts.
- [ ] Configure `MINIO_PUBLIC_ENDPOINT` / MinIO proxy so presigned URLs reach
      mobile clients.
- [ ] Set `MEDIAMTX_WHEP_BASE_URL` and `MEDIAMTX_HLS_BASE_URL` to client-
      reachable HTTPS endpoints, and set `MEDIAMTX_WEBRTC_ADDITIONAL_HOSTS`
      to the public MediaMTX IP/DNS name. Forward WebRTC ICE traffic on
      `8189/udp` (and `8189/tcp` where UDP is unavailable).
- [ ] Put MongoDB and MinIO on private networks; expose only the API.

## Topology

```
Flutter ──HTTPS──► Reverse proxy ──► FastAPI (N replicas)
                                        │
                     ├────► MongoDB (replica set)
                     ├────► MinIO (distributed/VM)
                     └────► MediaMTX (RTSP ingest / WHEP / HLS)
```

The backend registers each camera's RTSP source with MediaMTX on demand. CCTV
RTSP URLs and credentials are encrypted with `CCTV_CREDENTIALS_ENCRYPTION_KEY`.
Only the authorized CCTV stream endpoint returns client playback URLs. WebRTC
and HLS traffic then flows directly between the client and MediaMTX; configure
the public URL and ICE host to match the deployment and reverse proxy.

The backend is stateless, so it scales horizontally. MongoDB, MinIO, and
MediaMTX scale independently.

## Backup

**MongoDB**
- Use `mongodump` / replica-set snapshots on a schedule (e.g. hourly oplog +
  daily full).
- Retention: e.g. 7 daily, 4 weekly, 12 monthly.
- Restore: `mongorestore --uri ... <dump>`; then run `python -m app.bootstrap`
  to re-ensure indexes.

**MinIO**
- Object storage does **not** back up automatically. Configure bucket
  replication to a second MinIO/S3 target, or versioning + scheduled mirror.
- Retention and restore documented alongside the replica target.

**Test restores** periodically — an untested backup is not a backup.

## Observability

Structured request logs include method, path, status, latency, and a request id
(`x-request-id`). Secrets are never logged. The architecture leaves room to add
metrics (Prometheus), tracing, and error tracking later.
