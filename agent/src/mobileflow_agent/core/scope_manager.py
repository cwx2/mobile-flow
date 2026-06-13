"""Central orchestrator for client scope lifecycle management.

Module: core/scope_manager.py
Responsibility:
    Manages the full lifecycle of client scopes: creation, suspension,
    resumption, disposal, and capacity enforcement. All connection modes
    (LAN, Tunnel, Relay) go through the same registration pipeline via
    mode-specific IdentityStrategy implementations.

    Replaces the scope management logic previously embedded in websocket.py,
    decoupling scope lifecycle from WebSocket connection lifecycle. Scopes
    are now bound to stable client identities rather than ephemeral
    connection IDs, enabling seamless reconnection across all modes.

    Key responsibilities:
    - Unified register/unregister pipeline for all connection modes
    - Grace period management (suspend → timer → dispose)
    - LRU eviction when suspended scope count exceeds capacity
    - CLI session remapping on scope resume
    - Cleanup factory delegation for service-specific resource teardown

Used by:
    - server/websocket.py (delegates all scope operations here)
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Awaitable, Callable, Optional

from loguru import logger

from ..server.connection_manager import ConnectionMode
from .client_scope import ClientScope
from .identity_resolver import ClientIdentity, IdentityStrategy
from .scope_state import InvalidStateTransition, ScopeLifecycleState, ScopeStateEntry

if TYPE_CHECKING:
    from ..core.config import AgentConfig
    from ..services.cli_manager import CLIManager


# Type alias for the cleanup factory callback.
# websocket.py provides this to register service-specific cleanups
# (terminal, permissions, stream replay, test panel) on new scopes.
CleanupFactory = Callable[[str, "ClientScope"], Awaitable[None]]


@dataclass
class RegistrationResult:
    """Result of client registration via ScopeManager.register_client().

    Attributes:
        scope: The ClientScope instance (new or resumed).
        resumed: Whether an existing suspended scope was resumed.
        old_client_id: The previous client_id if resumed, used by callers
            to transfer resources (e.g., stream replay buffers).
    """

    scope: ClientScope
    resumed: bool
    old_client_id: str | None = None


class ScopeManager:
    """Orchestrates client scope lifecycle independent of transport.

    Manages scope creation, suspension, resumption, disposal, and
    capacity enforcement. All connection modes go through the same
    pipeline via IdentityStrategy.

    Attributes:
        _strategies: Registered identity strategies per ConnectionMode.
        _active_scopes: Currently active scopes keyed by client_id.
        _suspended_scopes: Suspended scopes keyed by stable_id.
        _identity_map: Maps client_id → ClientIdentity for active clients.
        _config: Agent configuration (grace period, max suspended, etc.).
        _cli_manager: CLI manager for session remapping on resume.
        _cleanup_factory: Optional callback for registering service-specific
            cleanups on new scopes (provided by websocket.py).
    """

    def __init__(
        self,
        config: AgentConfig,
        cli_manager: CLIManager,
        cleanup_factory: Optional[CleanupFactory] = None,
    ) -> None:
        """Initialize ScopeManager with configuration and dependencies.

        Args:
            config: Agent configuration providing grace period and capacity settings.
            cli_manager: CLI manager for session remapping on scope resume.
            cleanup_factory: Optional async callback that registers service-specific
                cleanups (terminal, permissions, stream replay, test panel) on a
                newly created scope. Keeps ScopeManager decoupled from handler services.
        """
        self._strategies: dict[ConnectionMode, IdentityStrategy] = {}
        self._active_scopes: dict[str, ScopeStateEntry] = {}
        self._suspended_scopes: dict[str, ScopeStateEntry] = {}
        self._identity_map: dict[str, ClientIdentity] = {}
        self._config = config
        self._cli_manager = cli_manager
        self._cleanup_factory = cleanup_factory

    # ── Strategy Registration ──

    def register_strategy(self, strategy: IdentityStrategy) -> None:
        """Register an identity strategy for a connection mode.

        Each mode can have exactly one strategy. Registering a new strategy
        for an already-registered mode replaces the previous one.

        Args:
            strategy: The IdentityStrategy implementation to register.
                Must implement the `mode` property and `resolve()` method.
        """
        self._strategies[strategy.mode] = strategy
        logger.debug(f"[ScopeManager] 注册身份策略: mode={strategy.mode.value}")

    # ── Client Registration ──

    async def register_client(
        self,
        client_id: str,
        mode: ConnectionMode,
        credentials: dict | None = None,
    ) -> RegistrationResult:
        """Unified client registration pipeline for all connection modes.

        Algorithm:
        1. Resolve stable identity via the mode's IdentityStrategy
        2. Check if a suspended scope exists for that identity
        3. If yes: cancel grace timer, resume scope, remap CLI sessions
        4. If no: create fresh scope with standard cleanups

        Args:
            client_id: Ephemeral WebSocket-level client identifier.
            mode: The connection mode (LAN, Tunnel, Relay).
            credentials: Mode-specific auth data for identity resolution.
                LAN: {"session_token": str}
                Tunnel: {"bearer_token": str}
                Relay: {"device_id": str}

        Returns:
            RegistrationResult with the scope and resume status.
        """
        logger.debug(
            f"[ScopeManager] register_client: "
            f"client_id={client_id[:12]}, mode={mode.value}"
        )

        # Step 1: Resolve stable identity
        identity = self._resolve_identity(mode, credentials)

        # Step 2: Attempt scope resume if identity is known
        if identity:
            entry = self._suspended_scopes.get(identity.stable_id)
            if entry and entry.state == ScopeLifecycleState.SUSPENDED:
                return await self._resume_scope(client_id, identity, entry)

        # Step 3: Create fresh scope
        scope = await self._create_scope(client_id)
        effective_identity = identity or ClientIdentity(
            stable_id=client_id, mode=mode
        )
        entry = ScopeStateEntry(
            state=ScopeLifecycleState.ACTIVE,
            identity_id=effective_identity.stable_id,
            scope=scope,
        )
        self._active_scopes[client_id] = entry
        if identity:
            self._identity_map[client_id] = identity

        logger.info(
            f"[ScopeManager] 新 scope 已创建: "
            f"client_id={client_id[:12]}, mode={mode.value}, "
            f"stable_id={effective_identity.stable_id[:16]}"
        )
        return RegistrationResult(scope=scope, resumed=False)

    # ── Client Unregistration ──

    async def unregister_client(self, client_id: str) -> None:
        """Handle client disconnection — suspend scope with grace period.

        Algorithm:
        1. Pop entry from _active_scopes
        2. If grace_period == 0: dispose immediately
        3. If grace_period > 0: suspend with timer
        4. If grace_period < 0: suspend without timer (never expire)
        5. Store in _suspended_scopes keyed by stable_id
        6. Call _enforce_capacity()

        Args:
            client_id: The disconnecting client's identifier.
        """
        entry = self._active_scopes.pop(client_id, None)
        if entry is None:
            logger.debug(
                f"[ScopeManager] unregister_client: "
                f"client_id={client_id[:12]} 不在活跃列表中（忽略）"
            )
            return

        identity = self._identity_map.pop(client_id, None)
        grace = self._config.scope.disconnect_grace_period

        if grace == 0:
            # No grace period — dispose immediately
            entry.transition(ScopeLifecycleState.DISPOSED)
            await entry.scope.dispose()
            logger.info(
                f"[ScopeManager] scope 已立即销毁（grace=0）: "
                f"client_id={client_id[:12]}"
            )
            return

        # Transition to suspended
        entry.transition(ScopeLifecycleState.SUSPENDED)
        entry.scope.cancelled.set()
        entry.suspended_at = time.time()

        # Determine stable_id for suspended map key
        stable_id = identity.stable_id if identity else client_id

        # Start grace timer (only if grace > 0; -1 means never expire)
        if grace > 0:
            async def _grace_timer_expired():
                """Dispose scope after grace period expires."""
                try:
                    await asyncio.sleep(grace)
                    # Timer expired — dispose the scope
                    if entry.state == ScopeLifecycleState.SUSPENDED:
                        entry.transition(ScopeLifecycleState.DISPOSED)
                        self._suspended_scopes.pop(stable_id, None)
                        await entry.scope.dispose()
                        logger.info(
                            f"[ScopeManager] grace 超时，scope 已销毁: "
                            f"stable_id={stable_id[:16]}"
                        )
                except asyncio.CancelledError:
                    pass

            entry.grace_timer = asyncio.create_task(_grace_timer_expired())
        else:
            # grace < 0: never expire — scope stays suspended indefinitely
            # until client reconnects or LRU eviction kicks in
            entry.grace_timer = None

        # Store in suspended map
        self._suspended_scopes[stable_id] = entry

        logger.info(
            f"[ScopeManager] scope 已挂起: "
            f"client_id={client_id[:12]}, stable_id={stable_id[:16]}, "
            f"grace={'永不过期' if grace < 0 else f'{grace}s'}"
        )

        # Enforce capacity
        await self._enforce_capacity()

    # ── Capacity Enforcement ──

    async def _enforce_capacity(self) -> None:
        """LRU eviction when suspended scope count exceeds max_suspended_scopes.

        Evicts the oldest suspended scope (smallest suspended_at timestamp)
        until the count is within the configured limit.

        Loop invariant: after each iteration, total suspended count decreases
        by 1, and the evicted entry is the one with the earliest suspended_at.
        """
        max_count = self._config.scope.max_suspended_scopes

        while len(self._suspended_scopes) > max_count:
            # Find oldest (LRU) — smallest suspended_at
            oldest_key = min(
                self._suspended_scopes,
                key=lambda k: self._suspended_scopes[k].suspended_at or 0,
            )
            oldest = self._suspended_scopes.pop(oldest_key)

            # Cancel its grace timer
            if oldest.grace_timer and not oldest.grace_timer.done():
                oldest.grace_timer.cancel()

            # Dispose the scope
            if oldest.state != ScopeLifecycleState.DISPOSED:
                oldest.transition(ScopeLifecycleState.DISPOSED)
            await oldest.scope.dispose()

            logger.warning(
                f"[ScopeManager] 容量淘汰（LRU）: "
                f"stable_id={oldest_key[:16]}, "
                f"suspended_count={len(self._suspended_scopes)}/{max_count}"
            )

    # ── Graceful Shutdown ──

    async def dispose_all(self) -> None:
        """Dispose all scopes (active and suspended) for graceful Agent shutdown.

        Cancels all grace timers, disposes all scopes, and clears all
        internal state. After this call, active_count and suspended_count
        are both 0.
        """
        logger.info(
            f"[ScopeManager] dispose_all: "
            f"active={self.active_count}, suspended={self.suspended_count}"
        )

        # Cancel all grace timers and dispose suspended scopes
        for stable_id, entry in list(self._suspended_scopes.items()):
            if entry.grace_timer and not entry.grace_timer.done():
                entry.grace_timer.cancel()
            if entry.state != ScopeLifecycleState.DISPOSED:
                entry.transition(ScopeLifecycleState.DISPOSED)
                await entry.scope.dispose()

        # Dispose active scopes
        for client_id, entry in list(self._active_scopes.items()):
            if entry.state != ScopeLifecycleState.DISPOSED:
                entry.transition(ScopeLifecycleState.DISPOSED)
                await entry.scope.dispose()

        # Clear all state
        self._active_scopes.clear()
        self._suspended_scopes.clear()
        self._identity_map.clear()

        logger.info("[ScopeManager] dispose_all 完成")

    # ── Properties ──

    @property
    def suspended_count(self) -> int:
        """Number of currently suspended scopes."""
        return len(self._suspended_scopes)

    @property
    def active_count(self) -> int:
        """Number of currently active scopes."""
        return len(self._active_scopes)

    # ── Private Helpers ──

    def _resolve_identity(
        self, mode: ConnectionMode, credentials: dict | None
    ) -> Optional[ClientIdentity]:
        """Resolve stable identity via the mode's registered strategy.

        Never raises exceptions — returns None on resolution failure,
        causing the caller to fall through to fresh scope creation.

        Args:
            mode: The connection mode to look up the strategy for.
            credentials: Mode-specific authentication data.

        Returns:
            ClientIdentity if resolution succeeds, None otherwise.
        """
        strategy = self._strategies.get(mode)
        if not strategy:
            logger.debug(
                f"[ScopeManager] 无身份策略: mode={mode.value}"
            )
            return None

        if not credentials:
            logger.debug(
                f"[ScopeManager] 无凭证，跳过身份解析: mode={mode.value}"
            )
            return None

        identity = strategy.resolve(credentials)
        if identity:
            logger.debug(
                f"[ScopeManager] 身份解析成功: "
                f"mode={mode.value}, stable_id={identity.stable_id[:16]}"
            )
        else:
            logger.warning(
                f"[ScopeManager] 身份解析失败: mode={mode.value}"
            )
        return identity

    async def _resume_scope(
        self,
        client_id: str,
        identity: ClientIdentity,
        entry: ScopeStateEntry,
    ) -> RegistrationResult:
        """Resume a suspended scope for a reconnecting client.

        Cancels the grace timer, transitions SUSPENDED→ACTIVE, resets the
        scope, remaps CLI sessions, and moves the entry from suspended to
        active maps.

        Args:
            client_id: The new ephemeral WebSocket client_id.
            identity: The resolved stable identity.
            entry: The suspended ScopeStateEntry to resume.

        Returns:
            RegistrationResult with resumed=True and the old_client_id.
        """
        # Cancel grace timer
        if entry.grace_timer and not entry.grace_timer.done():
            entry.grace_timer.cancel()
            entry.grace_timer = None

        # Transition state
        entry.transition(ScopeLifecycleState.ACTIVE)
        entry.suspended_at = None

        # Capture old client_id before updating
        old_client_id = entry.scope.client_id

        # Reset scope for reuse (clears cancelled event)
        entry.scope.reset()

        # Update scope's client_id to the new connection
        entry.scope.client_id = client_id

        # Remap CLI sessions from old to new client_id
        self._cli_manager.remap_client(old_client_id, client_id)

        # Move from suspended to active
        del self._suspended_scopes[identity.stable_id]
        self._active_scopes[client_id] = entry
        self._identity_map[client_id] = identity

        logger.info(
            f"[ScopeManager] scope 已恢复: "
            f"old_client={old_client_id[:12]}, new_client={client_id[:12]}, "
            f"stable_id={identity.stable_id[:16]}"
        )

        return RegistrationResult(
            scope=entry.scope,
            resumed=True,
            old_client_id=old_client_id,
        )

    async def _create_scope(self, client_id: str) -> ClientScope:
        """Create a new ClientScope and register standard cleanups.

        Always registers CLI cleanup (ScopeManager owns this relationship).
        Delegates service-specific cleanups (terminal, permissions, stream
        replay, test panel) to the cleanup_factory callback provided by
        websocket.py, keeping ScopeManager decoupled from handler services.

        Args:
            client_id: The client's identifier for the new scope.

        Returns:
            The newly created ClientScope with cleanups registered.
        """
        scope = ClientScope(client_id)

        # Always register CLI cleanup — shut down providers and cancel
        # background tasks when scope is disposed
        scope.on_dispose(lambda: self._cli_manager.cleanup_sessions(client_id))

        # Delegate service-specific cleanups to the factory
        if self._cleanup_factory:
            await self._cleanup_factory(client_id, scope)

        return scope
