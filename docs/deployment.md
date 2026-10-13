# Deployment

## Local development

Before starting the Docker stack, set `CCTV_CREDENTIALS_ENCRYPTION_KEY` in
`infrastructure/.env` to a stable URL-safe base64 key generated from 32 random
bytes. For a native backend, set the same key in `backend/.env`. The backend
requires it to save CCTV IP addresses and stream credentials; Compose refuses
to start without it.

```bash
# 1. Start Mongo, MinIO, and the API
docker compose -f infrastructure/docker-compose.yml up -d --build

# 2. API is at http://localhost:8000  (docs at /docs)
# 3. Default admin (created only if the DB is empty):
#    admin / DEFAULT_ADMIN_PASSWORD   <-- change immediately:
#    python -m scripts.set_password admin
```

To run the backend directly (without Docker):

```bash
cd backend
python -m venv .venv && . .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                                # fill in values
python -m app.bootstrap                             # indexes + default admin
uvicorn app.main:app --reload
```

## Production checklist

- [ ] Set `ENVIRONMENT=production` (disables `/docs`, `/redoc`, `/openapi.json`).
- [ ] Use a long random `JWT_SECRET_KEY`
      (`python -c "import secrets; print(secrets.token_urlsafe(64))"`).
- [ ] Set `MONGODB_URI` to a secured/authenticated cluster.
- [ ] Set strong, unique MinIO credentials; keep the bucket private.
- [ ] Serve everything over **HTTPS** (TLS at a reverse proxy / load balancer).
- [ ] Set `CORS_ORIGINS` to the exact allowed origins — never `*`.
- [ ] Restrict rate limiting to a shared store (Redis) if running >1 replica.
- [ ] Rotate the default admin password; disable/remove unused seed accounts.
- [ ] Configure `MINIO_PUBLIC_ENDPOINT` / MinIO proxy so presigned URLs reach
      mobile clients.
- [ ] Put MongoDB and MinIO on private networks; expose only the API.

## Topology

```
Flutter ──HTTPS──► Reverse proxy ──► FastAPI (N replicas)
                                        │
                     ┌──────────────────┴──────────────────┐
                     ▼                                     ▼
              MongoDB (replica set)               MinIO (distributed/VM)
```

The backend is stateless, so it scales horizontally. MongoDB and MinIO scale
independently.

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
