"""MobileFlow Relay Server — FastAPI application factory.

Zero-knowledge message relay: forwards E2E encrypted messages between
Agent and App without decrypting content.

Endpoints:
  WebSocket:
    /ws/agent/{device_id}  — Agent connection (with Ed25519 auth)
    /ws/app/{device_id}    — App connection
  REST:
    POST /v1/auth          — Ed25519 signature authentication
    GET  /health           — Health check
"""

from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass, field
from typing import Any, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from loguru import logger

from .auth import verify_ed25519_challenge, generate_auth_token, AuthToken


# ── Data models ──


@dataclass
class ConnectedDevice:
    """A connected device (Agent or App)."""
    device_id: str
    role: str  # "agent" or "app"
    websocket: WebSocket
    target_device_id: str = ""
    connected_at: float = field(default_factory=time.time)
    public_key: str = ""


class RelayHub:
    """Message relay hub with offline buffering and rate limiting.

    Zero-knowledge: does not decrypt message content, only reads
    routing fields in the envelope.
    """

    def __init__(self):
        self._devices: dict[str, ConnectedDevice] = {}
        self._offline_messages: dict[str, list[dict[str, Any]]] = {}
        self._rate_limits: dict[str, tuple[int, float]] = {}

    @property
    def device_count(self) -> int:
        return len(self._devices)

    def register(self, device: ConnectedDevice) -> None:
        self._devices[device.device_id] = device
        logger.info(f"设备注册: {device.device_id[:12]}... ({device.role})")

    def unregister(self, device_id: str) -> None:
        if device_id in self._devices:
            del self._devices[device_id]
            logger.info(f"设备注销: {device_id[:12]}...")

    def get_device(self, device_id: str) -> Optional[ConnectedDevice]:
        return self._devices.get(device_id)

    def find_target(self, device: ConnectedDevice) -> Optional[ConnectedDevice]:
        """Find the target device for routing."""
        if device.role == "app" and device.target_device_id:
            return self._devices.get(device.target_device_id)
        if device.role == "agent":
            for d in self._devices.values():
                if d.role == "app" and d.target_device_id == device.device_id:
                    return d
        return None

    async def forward_message(self, from_device: ConnectedDevice, raw_message: str) -> bool:
        """Forward a message to the target device (zero-knowledge)."""
        if not self._check_rate_limit(from_device.device_id):
            logger.warning(f"限流: {from_device.device_id[:12]}...")
            return False

        target = self.find_target(from_device)
        if target is None:
            self._store_offline(from_device, raw_message)
            return False

        try:
            await target.websocket.send_text(raw_message)
            return True
        except Exception as e:
            logger.warning(f"转发失败: {e}")
            self.unregister(target.device_id)
            return False

    async def flush_offline(self, device_id: str) -> int:
        """Flush buffered offline messages to a reconnected device."""
        messages = self._offline_messages.pop(device_id, [])
        if not messages:
            return 0
        device = self._devices.get(device_id)
        if not device:
            return 0
        sent = 0
        for msg in messages:
            try:
                await device.websocket.send_text(json.dumps(msg))
                sent += 1
            except Exception:
                break
        if sent:
            logger.info(f"推送 {sent} 条离线消息到 {device_id[:12]}...")
        return sent

    def _store_offline(self, from_device: ConnectedDevice, raw_message: str) -> None:
        """Buffer offline message (max 100 per device, 24h expiry)."""
        target_id = from_device.target_device_id
        if from_device.role == "agent":
            for d in self._devices.values():
                if d.role == "app" and d.target_device_id == from_device.device_id:
                    target_id = d.device_id
                    break
            else:
                return
        if target_id not in self._offline_messages:
            self._offline_messages[target_id] = []
        queue = self._offline_messages[target_id]
        if len(queue) >= 100:
            queue.pop(0)
        queue.append({"data": raw_message, "ts": time.time()})

    def _check_rate_limit(self, device_id: str) -> bool:
        """Rate limit: max 300 messages per minute per device."""
        now = time.time()
        count, window_start = self._rate_limits.get(device_id, (0, now))
        if now - window_start > 60:
            self._rate_limits[device_id] = (1, now)
            return True
        if count >= 300:
            return False
        self._rate_limits[device_id] = (count + 1, window_start)
        return True

    def cleanup_expired_offline(self) -> int:
        """Clean up expired offline messages (24h TTL)."""
        now = time.time()
        cleaned = 0
        for device_id in list(self._offline_messages.keys()):
            messages = self._offline_messages[device_id]
            before = len(messages)
            messages[:] = [m for m in messages if now - m.get("ts", 0) < 86400]
            cleaned += before - len(messages)
            if not messages:
                del self._offline_messages[device_id]
        return cleaned


# ── Application factory ──


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    app = FastAPI(title="MobileFlow Relay Server", version="0.1.0")
    hub = RelayHub()
    _auth_tokens: dict[str, AuthToken] = {}

    @app.get("/health")
    async def health():
        return {"status": "ok", "devices": hub.device_count}

    @app.post("/v1/auth")
    async def auth(body: dict):
        challenge = body.get("challenge", "")
        public_key = body.get("publicKey", body.get("public_key", ""))
        signature = body.get("signature", "")
        if not verify_ed25519_challenge(challenge, public_key, signature):
            return {"success": False, "error": "signature verification failed"}
        device_id = public_key[:16]
        token = generate_auth_token(device_id, public_key)
        _auth_tokens[token.token] = token
        return {"success": True, "token": token.token}

    @app.websocket("/ws/agent/{device_id}")
    async def ws_agent(websocket: WebSocket, device_id: str):
        await websocket.accept()
        logger.info(f"Agent 连接: {device_id[:12]}...")
        device = ConnectedDevice(device_id=device_id, role="agent", websocket=websocket)
        try:
            auth_raw = await asyncio.wait_for(websocket.receive_text(), timeout=10)
            auth_msg = json.loads(auth_raw)
            if auth_msg.get("type") == "auth":
                if not verify_ed25519_challenge(
                    auth_msg.get("challenge", ""),
                    auth_msg.get("public_key", ""),
                    auth_msg.get("signature", ""),
                ):
                    await websocket.send_text(json.dumps({"type": "auth_error", "error": "invalid signature"}))
                    await websocket.close()
                    return
                device.public_key = auth_msg.get("public_key", "")
                await websocket.send_text(json.dumps({"type": "auth_ok"}))
        except asyncio.TimeoutError:
            await websocket.close()
            return
        hub.register(device)
        await hub.flush_offline(device_id)
        try:
            async for raw in websocket.iter_text():
                await hub.forward_message(device, raw)
        except WebSocketDisconnect:
            pass
        finally:
            hub.unregister(device_id)

    @app.websocket("/ws/app/{device_id}")
    async def ws_app(websocket: WebSocket, device_id: str, target: str = Query(default="")):
        await websocket.accept()
        logger.info(f"App 连接: {device_id[:12]}... → Agent: {target[:12]}...")
        device = ConnectedDevice(
            device_id=device_id, role="app", websocket=websocket, target_device_id=target,
        )
        hub.register(device)
        await hub.flush_offline(device_id)
        try:
            async for raw in websocket.iter_text():
                await hub.forward_message(device, raw)
        except WebSocketDisconnect:
            pass
        finally:
            hub.unregister(device_id)

    @app.on_event("startup")
    async def startup():
        asyncio.create_task(_cleanup_loop(hub))

    return app


async def _cleanup_loop(hub: RelayHub):
    """Clean up expired offline messages every hour."""
    while True:
        await asyncio.sleep(3600)
        cleaned = hub.cleanup_expired_offline()
        if cleaned > 0:
            logger.info(f"清理 {cleaned} 条过期离线消息")
