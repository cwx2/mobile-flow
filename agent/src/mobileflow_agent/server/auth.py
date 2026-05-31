"""Authentication manager for WebSocket server.

Handles device pairing, session token generation, and session validation.

Connection password is persistent: generated once on first startup, saved to
``~/.mobileflow/agent_identity.json``, and reused across restarts. Users can
override it via config (``pair_token``) or environment variable
(``MOBILEFLOW_PAIR_TOKEN``). The password can be used repeatedly — it is NOT
invalidated after successful verification (unlike the old one-time pairing code).

Sessions are persisted to disk so they survive Agent restarts — this enables
the App to auto-reconnect without re-pairing every time the Agent restarts.

Brute-force protection: global lockout after N consecutive failures
(configurable via ConnectionConfig.pair_max_failures / pair_lockout_seconds).
"""

from __future__ import annotations

import base64
import secrets
import string
import time
from pathlib import Path
from typing import NamedTuple, Optional

from loguru import logger


class SessionVerifyResult(NamedTuple):
    """Result of session token verification.

    Using NamedTuple instead of a bare tuple so callers access fields by
    name and new fields can be added without breaking existing unpacking.

    Attributes:
        success: True if the session is valid and not expired.
        error_code: None on success; "token_not_found" or "session_expired"
            on failure.
        secret: The 32-byte shared encryption secret, or None on failure.
        client_id: The original client_id that created this session.
            Empty string if the token was not found.
    """

    success: bool
    error_code: Optional[str]
    secret: Optional[bytes]
    client_id: str

from ..core.config import AgentConfig
from ..utils.json_file import load_json_file, save_json_file


class AuthManager:
    """Manages connection password and session tokens for client authentication.

    The connection password (pair_token) is persistent and reusable:
    - First startup: auto-generate 8-char alphanumeric password, save to disk
    - Subsequent startups: load from disk
    - User override: config file or MOBILEFLOW_PAIR_TOKEN env var takes priority

    Sessions (token → client_id, expiry, secret) are persisted to
    ``~/.mobileflow/auth_sessions.json`` so they survive Agent restarts.

    Attributes:
        config: Agent configuration (provides session timeout, brute-force
            thresholds via config.connection, etc.).
    """

    def __init__(self, config: AgentConfig):
        self.config = config
        self._pair_token: Optional[str] = None
        # session_token -> (client_id, expiry_timestamp)
        self._sessions: dict[str, tuple[str, float]] = {}
        # session_token -> 32-byte shared secret for LAN encryption
        self._session_secrets: dict[str, bytes] = {}
        # Global brute-force tracking (not per-source, prevents IP rotation bypass)
        self._global_fail_count: int = 0
        self._global_fail_first_ts: float = 0.0
        # Persistence file paths
        self._data_dir = config.ensure_data_dir()
        self._identity_file = self._data_dir / "agent_identity.json"
        self._sessions_file = self._data_dir / "auth_sessions.json"
        self._load_sessions()

    # ── Session persistence ──

    def _load_sessions(self):
        """Load persisted sessions from disk on startup.

        Automatically cleans up expired sessions during load so stale
        entries don't accumulate across restarts.
        """
        data = load_json_file(self._sessions_file, default={})
        if not data:
            return
        try:
            now = time.time()
            loaded = 0
            for entry in data.get("sessions", []):
                token = entry["token"]
                expiry = entry["expiry"]
                if expiry <= now:
                    continue
                self._sessions[token] = (entry["client_id"], expiry)
                secret_b64 = entry.get("secret")
                if secret_b64:
                    self._session_secrets[token] = base64.b64decode(secret_b64)
                loaded += 1
            if loaded:
                logger.info(f"🔑 恢复了 {loaded} 个会话")
        except Exception as e:
            logger.warning(f"加载会话文件失败: {e}")

    def _save_sessions(self):
        """Persist all non-expired sessions to disk.

        Called after create_session and cleanup_expired to keep the
        file in sync with memory.
        """
        try:
            now = time.time()
            entries = []
            for token, (client_id, expiry) in self._sessions.items():
                if expiry <= now:
                    continue
                entry = {
                    "token": token,
                    "client_id": client_id,
                    "expiry": expiry,
                }
                secret = self._session_secrets.get(token)
                if secret:
                    entry["secret"] = base64.b64encode(secret).decode("ascii")
                entries.append(entry)
            save_json_file(self._sessions_file, {"sessions": entries})
        except Exception as e:
            logger.warning(f"保存会话文件失败: {e}")

    # ── Identity persistence ──

    def _load_identity(self) -> Optional[str]:
        """Load saved connection password from identity file.

        Returns:
            The saved password string, or None if not found.
        """
        data = load_json_file(self._identity_file, default=None)
        if data and isinstance(data, dict):
            return data.get("pair_token")
        return None

    def _save_identity(self, pair_token: str):
        """Save connection password to identity file.

        Merges with existing identity data (e.g. device_id) to avoid
        overwriting other fields.

        Args:
            pair_token: The password to persist.
        """
        try:
            data = load_json_file(self._identity_file, default={})
            if not isinstance(data, dict):
                data = {}
            data["pair_token"] = pair_token
            save_json_file(self._identity_file, data)
            logger.debug("连接密码已持久化")
        except Exception as e:
            logger.warning(f"保存身份文件失败: {e}")

    # ── Connection password ──

    def ensure_pair_token(self) -> tuple[str, bool]:
        """Ensure a connection password exists, generating one if needed.

        Priority chain (high → low):
        1. Config / env var (``config.pair_token`` / ``MOBILEFLOW_PAIR_TOKEN``)
        2. Saved on disk (``~/.mobileflow/agent_identity.json``)
        3. Auto-generate 8-char alphanumeric password and save

        Returns:
            A tuple of (password, is_new) where is_new indicates whether
            the password was just generated (True) or loaded (False).
            is_new is used to decide whether to print the password in
            the terminal (only on first generation).
        """
        # Priority 1: user-configured password
        if self.config.pair_token:
            self._pair_token = self.config.pair_token
            logger.debug("使用配置文件中的连接密码")
            return (self._pair_token, False)

        # Priority 2: saved on disk
        saved = self._load_identity()
        if saved:
            self._pair_token = saved
            logger.debug("从磁盘恢复连接密码")
            return (self._pair_token, False)

        # Priority 3: auto-generate
        alphabet = string.ascii_letters + string.digits
        self._pair_token = "".join(
            secrets.choice(alphabet) for _ in range(8)
        )
        self._save_identity(self._pair_token)
        logger.info("首次启动，已生成连接密码")
        return (self._pair_token, True)

    def reset_pair_token(self) -> str:
        """Reset the connection password to a new random value.

        Generates a new 8-char alphanumeric password, saves to disk,
        and returns it. Existing sessions remain valid (they use
        session_token, not the connection password).

        Returns:
            The new password string.
        """
        alphabet = string.ascii_letters + string.digits
        self._pair_token = "".join(
            secrets.choice(alphabet) for _ in range(8)
        )
        self._save_identity(self._pair_token)
        logger.info("连接密码已重置")
        return self._pair_token

    def verify_pair_token(self, token: str, source: str = "") -> tuple[bool, str | None]:
        """Verify a connection password with global brute-force protection.

        Uses global lockout (not per-source) to prevent IP rotation bypass.
        After ``pair_max_failures`` consecutive failures within
        ``pair_lockout_seconds``, ALL attempts are rejected until the
        lockout window expires.

        The password is NOT invalidated after success — it can be reused
        for multiple connections.

        Args:
            token: The password to verify.
            source: Identifier of the request origin (for logging only).

        Returns:
            A tuple of (success, error_code):
            - ``(True, None)`` on successful verification.
            - ``(False, "lockout")`` if globally locked out.
            - ``(False, "invalid")`` if the password does not match.
        """
        max_failures = self.config.connection.pair_max_failures
        lockout_seconds = self.config.connection.pair_lockout_seconds

        # Check global lockout
        if self._global_fail_count >= max_failures:
            elapsed = time.time() - self._global_fail_first_ts
            if elapsed < lockout_seconds:
                remaining = lockout_seconds - elapsed
                logger.warning(
                    f"全局锁定中: 剩余={remaining:.0f}s, source={source}"
                )
                return (False, "lockout")
            # Lockout expired, reset
            self._global_fail_count = 0
            self._global_fail_first_ts = 0.0

        if self._pair_token is None:
            self._record_failure()
            logger.warning(
                f"密码验证失败（未设置密码）: source={source}, "
                f"累计失败={self._global_fail_count}"
            )
            return (False, "invalid")

        valid = secrets.compare_digest(token, self._pair_token)
        if valid:
            # Reset failure counter on success
            self._global_fail_count = 0
            self._global_fail_first_ts = 0.0
            logger.info(f"密码验证成功: source={source}")
            return (True, None)
        else:
            self._record_failure()
            logger.warning(
                f"密码验证失败: source={source}, "
                f"累计失败={self._global_fail_count}"
            )
            return (False, "invalid")

    def _record_failure(self):
        """Record a global authentication failure for lockout tracking."""
        if self._global_fail_count == 0:
            self._global_fail_first_ts = time.time()
        self._global_fail_count += 1

    # ── Sessions ──

    def create_session(self, client_id: str, secret: bytes) -> str:
        """Create a new session token for an authenticated client.

        Generates a URL-safe session token, stores it with the client ID and
        expiry, associates the encryption secret, and persists to disk so
        the session survives Agent restarts.

        Args:
            client_id: Unique identifier of the connecting client.
            secret: 32-byte shared secret for LAN message-level encryption.

        Returns:
            A URL-safe session token string.
        """
        session_token = secrets.token_urlsafe(32)
        expires = time.time() + self.config.security.session_timeout
        self._sessions[session_token] = (client_id, expires)
        self._session_secrets[session_token] = secret
        self._save_sessions()
        logger.info(
            f"创建会话: client={client_id}, "
            f"timeout={self.config.security.session_timeout}s"
        )
        return session_token

    def update_session_client(self, session_token: str, new_client_id: str) -> None:
        """Update the client_id associated with a session token.

        Called after scope resumption: the reconnecting client gets a new
        WebSocket-level client_id, but the session token stays the same.
        Without this update, the next reconnect would look up the old
        client_id in _suspended and fail to find the scope.

        Args:
            session_token: The session token to update.
            new_client_id: The new client_id to associate.
        """
        session = self._sessions.get(session_token)
        if session is None:
            return
        _, expires = session
        self._sessions[session_token] = (new_client_id, expires)
        self._save_sessions()
        logger.debug(f"会话 client_id 已更新: {new_client_id}")

    def verify_session(self, session_token: str) -> SessionVerifyResult:
        """Verify that a session token is valid and not expired.

        Distinguishes between "not found" and "expired" to allow the App to
        show appropriate error messages and decide whether to prompt for
        re-pairing or just reconnection.

        Expired sessions are automatically removed from the store.

        Args:
            session_token: The token to verify.

        Returns:
            SessionVerifyResult with named fields: success, error_code,
            secret, client_id.
        """
        session = self._sessions.get(session_token)
        if session is None:
            logger.debug("会话验证失败: token 不存在")
            return SessionVerifyResult(success=False, error_code="token_not_found", secret=None, client_id="")

        client_id, expires = session
        if time.time() > expires:
            del self._sessions[session_token]
            self._session_secrets.pop(session_token, None)
            self._save_sessions()
            logger.info(f"会话过期: {client_id}")
            return SessionVerifyResult(success=False, error_code="session_expired", secret=None, client_id=client_id)

        secret = self._session_secrets.get(session_token)
        return SessionVerifyResult(success=True, error_code=None, secret=secret, client_id=client_id)

    def cleanup_expired(self):
        """Remove all expired sessions from the store."""
        now = time.time()
        expired = [
            token
            for token, (_, expires) in self._sessions.items()
            if now > expires
        ]
        for token in expired:
            del self._sessions[token]
            self._session_secrets.pop(token, None)
        if expired:
            self._save_sessions()
            logger.debug(f"清理过期会话: {len(expired)} 个")
