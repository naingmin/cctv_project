"""API v1 router aggregation."""
from fastapi import APIRouter

from app.api.v1 import audit, auth, cctv, dashboard_ws, uploads, users

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(cctv.router)
api_router.include_router(uploads.router)
api_router.include_router(users.router)
api_router.include_router(audit.router)
api_router.include_router(dashboard_ws.router)
