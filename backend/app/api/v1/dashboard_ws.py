"""Authenticated dashboard status WebSocket."""
from __future__ import annotations

import asyncio
from typing import Any

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from pymongo.database import Database

from app.api.deps import CurrentUser, get_user_from_token
from app.core.errors import ForbiddenError, UnauthorizedError
from app.core.rbac import Permission, role_has_permission
from app.db.mongo import get_db
from app.services import cctv_service

router = APIRouter(tags=["Dashboard"])


class DashboardConnectionManager:
    def __init__(self) -> None:
        self._users: dict[WebSocket, CurrentUser] = {}

    async def connect(self, websocket: WebSocket, user: CurrentUser) -> None:
        self._users[websocket] = user

    def disconnect(self, websocket: WebSocket) -> None:
        self._users.pop(websocket, None)

    async def broadcast_status_update(self, db: Database, doc: dict[str, Any]) -> None:
        """Send scoped counts to every dashboard and the CCTV only if visible."""
        record_id = str(doc["_id"])
        disconnected = []
        for websocket, user in list(self._users.items()):
            visible = await asyncio.to_thread(
                cctv_service.get_by_id, db, record_id, user=user
            )
            stats = await asyncio.to_thread(cctv_service.global_stats, db, user)
            payload = {
                "type": "dashboard_update",
                "cctv": (
                    {
                        "id": record_id,
                        "cctv_id": doc["cctv_id"],
                        "status": doc.get("status", "INACTIVE"),
                        "last_checked": (
                            doc["last_checked"].isoformat()
                            if doc.get("last_checked")
                            else None
                        ),
                    }
                    if visible
                    else None
                ),
                "stats": stats,
            }
            try:
                await websocket.send_json(payload)
            except (OSError, RuntimeError, WebSocketDisconnect):
                disconnected.append(websocket)
        for websocket in disconnected:
            self.disconnect(websocket)

    async def handle(self, websocket: WebSocket, db: Database) -> None:
        await websocket.accept()
        try:
            auth_message = await asyncio.wait_for(
                websocket.receive_json(), timeout=10
            )
            if not isinstance(auth_message, dict):
                await websocket.close(code=4401, reason="Authentication required.")
                return
            token = auth_message.get("token")
            if (
                auth_message.get("type") != "authenticate"
                or not isinstance(token, str)
            ):
                await websocket.close(code=4401, reason="Authentication required.")
                return
            user = await asyncio.to_thread(get_user_from_token, token, db)
            if not role_has_permission(user.role, Permission.CCTV_READ):
                raise ForbiddenError()
            await self.connect(websocket, user)
            await websocket.send_json({"type": "connected"})
            while True:
                await websocket.receive_text()
        except (UnauthorizedError, ForbiddenError):
            await websocket.close(code=4403, reason="Authentication failed.")
        except ValueError:
            await websocket.close(code=4401, reason="Invalid authentication message.")
        except asyncio.TimeoutError:
            await websocket.close(code=4401, reason="Authentication timed out.")
        except WebSocketDisconnect:
            pass
        finally:
            self.disconnect(websocket)


dashboard_connections = DashboardConnectionManager()


@router.websocket("/ws/dashboard")
async def dashboard_websocket(
    websocket: WebSocket,
    db: Database = Depends(get_db),
) -> None:
    await dashboard_connections.handle(websocket, db)
