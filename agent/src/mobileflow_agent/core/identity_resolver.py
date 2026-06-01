"""Identity resolution strategies for stable client identification.

Module: core/identity_resolver.py
Responsibility:
    Provides a strategy pattern for extracting stable client identities
    from mode-specific credentials. Each connection mode (LAN, Tunnel,
    Relay) has its own strategy that produces a deterministic stable_id
    independent of the ephemeral WebSocket client_id.

    The stable_id enables scope resume across reconnections: when a
    client disconnects and reconnects, the same stable_id maps to the
    same suspended scope, allowing seamless session recovery.

    Strategies never raise exceptions — they return None on failure
    and log a warning. This ensures that identity resolution failures
    degrade gracefully to fresh scope creation.

Used by:
    - core/scope_manager.py (resolves identity during register_client)
"""

from __future__ import annotations

import hashlib
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import TYPE_CHECKING, Optional

from loguru import logger

from ..server.connection_manager import ConnectionMode

if TYPE_CHECKING:
    from ..server.auth import AuthManager


@dataclass(frozen=True)
class ClientIdentity:
    """Stable identity for a client across reconnections.

    Frozen dataclass ensures identity objects are immutable and hashable,
    suitable for use as dict keys in the scope manager.

    Attributes:
        stable_id: Mode-specific stable identifier (original client_id
            for LAN, SHA-256 hash for Tunnel, device_id for Relay).
        mode: The connection mode that produced this identity.
        metadata: Optional mode-specific metadata (e.g., device_name).
    """

    stable_id: str
    mode: ConnectionMode
    metadata: dict | None = None


class IdentityStrategy(ABC):
    """Strategy interface for extracting stable identity from credentials.

    Each connection mode implements this to provide its own identity
    extraction logic. New modes (USB, BT) only need to implement this
    interface and register via ScopeManager.register_strategy() to get
    full scope resume support.
    """

    @abstractmethod
    def resolve(self, credentials: dict) -> Optional[ClientIdentity]:
        """Extract stable identity from mode-specific credentials.

        Args:
            credentials: Mode-specific authentication data.
                LAN: {"session_token": str}
                Tunnel: {"bearer_token": str}
                Relay: {"device_id": str}

        Returns:
            ClientIdentity if identity can be determined, None if
            credentials are missing/invalid or verification fails.
        """
        ...

    @property
    @abstractmethod
    def mode(self) -> ConnectionMode:
        """The connection mode this strategy handles."""
        ...


class LANIdentityStrategy(IdentityStrategy):
    """LAN mode: identity from session_token via AuthManager.verify_session().

    Uses the AuthManager to verify the session token and extract the
    original client_id that created the session. This client_id serves
    as the stable identity for scope resume.

    Attributes:
        _auth: Reference to the AuthManager for session verification.
    """

    def __init__(self, auth_manager: AuthManager) -> None:
        """Initialize with AuthManager dependency.

        Args:
            auth_manager: The AuthManager instance used to verify
                session tokens and extract original client_id.
        """
        self._auth = auth_manager

    @property
    def mode(self) -> ConnectionMode:
        """The connection mode this strategy handles."""
        return ConnectionMode.LAN

    def resolve(self, credentials: dict) -> Optional[ClientIdentity]:
        """Resolve LAN identity from session token.

        Calls auth.verify_session(token) to validate the token and
        extract the original client_id. Returns None if the token is
        missing, empty, or verification fails (expired/not found).

        Args:
            credentials: Must contain {"session_token": str}.

        Returns:
            ClientIdentity with stable_id=original_client_id on success,
            None if token is missing or session verification fails.
        """
        try:
            session_token = credentials.get("session_token", "")
            if not session_token:
                logger.warning("LAN 身份解析失败: session_token 为空")
                return None

            result = self._auth.verify_session(session_token)
            if not result.success:
                logger.warning(
                    f"LAN 身份解析失败: error_code={result.error_code}"
                )
                return None

            return ClientIdentity(
                stable_id=result.client_id,
                mode=ConnectionMode.LAN,
            )
        except Exception as e:
            logger.warning(f"LAN 身份解析异常: error={e}")
            return None


class TunnelIdentityStrategy(IdentityStrategy):
    """Tunnel mode: identity from SHA-256 hash of Bearer Token.

    Uses the SHA-256 hash of the bearer token as the stable identity.
    This ensures the raw token is never stored in the scope manager
    while still providing a deterministic mapping from token to identity.
    """

    @property
    def mode(self) -> ConnectionMode:
        """The connection mode this strategy handles."""
        return ConnectionMode.TUNNEL

    def resolve(self, credentials: dict) -> Optional[ClientIdentity]:
        """Resolve Tunnel identity from bearer token hash.

        Computes SHA-256 hash of the bearer token to produce a stable_id.
        The same bearer token always produces the same hash (deterministic).

        Args:
            credentials: Must contain {"bearer_token": str}.

        Returns:
            ClientIdentity with stable_id=sha256_hex on success,
            None if bearer_token is missing or empty.
        """
        try:
            bearer_token = credentials.get("bearer_token", "")
            if not bearer_token:
                logger.warning("Tunnel 身份解析失败: bearer_token 为空")
                return None

            hash_hex = hashlib.sha256(bearer_token.encode("utf-8")).hexdigest()
            return ClientIdentity(
                stable_id=hash_hex,
                mode=ConnectionMode.TUNNEL,
            )
        except Exception as e:
            logger.warning(f"Tunnel 身份解析异常: error={e}")
            return None


class RelayIdentityStrategy(IdentityStrategy):
    """Relay mode: identity from envelope 'from' field (device_id).

    Uses the device_id directly as the stable identity. In Relay mode,
    the device_id is a persistent identifier assigned to the mobile
    device, making it naturally stable across reconnections.
    """

    @property
    def mode(self) -> ConnectionMode:
        """The connection mode this strategy handles."""
        return ConnectionMode.RELAY

    def resolve(self, credentials: dict) -> Optional[ClientIdentity]:
        """Resolve Relay identity from device_id.

        Uses the device_id field directly as the stable_id. The device_id
        is a persistent identifier for the mobile device.

        Args:
            credentials: Must contain {"device_id": str}.

        Returns:
            ClientIdentity with stable_id=device_id on success,
            None if device_id is missing or empty.
        """
        try:
            device_id = credentials.get("device_id", "")
            if not device_id:
                logger.warning("Relay 身份解析失败: device_id 为空")
                return None

            return ClientIdentity(
                stable_id=device_id,
                mode=ConnectionMode.RELAY,
            )
        except Exception as e:
            logger.warning(f"Relay 身份解析异常: error={e}")
            return None
