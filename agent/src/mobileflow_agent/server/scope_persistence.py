"""Scope metadata persistence for Agent restart recovery.

Module: server/scope_persistence.py
Responsibility:
    Saves minimal scope metadata to disk so that after Agent restart:
    1. App connects with existing session_token
    2. Agent recognizes the token (AuthManager persists sessions)
    3. Agent checks disk for replay data via stable_id
    4. StreamReplay restored from disk JSONL
    5. App receives streaming_state → requests chat.replay
    6. User sees AI output without re-running anything

    Only the stream replay data needs persisting for the "see previous
    output" use case. CLI process state cannot be restored (must re-init).

Design reference:
    - LibreChat: Redis Streams + job metadata hash
    - Vercel resumable-stream: Redis pub/sub + stream ID tracking
    - Our adaptation: filesystem JSONL (no Redis needed for local Agent)

File layout:
    ~/.mobileflow/replay/{stable_id}/current_turn.jsonl
    ~/.mobileflow/replay/{stable_id}/turn_meta.json

Called by:
    - server/websocket.py on scope creation (provides persist_path)
    - server/websocket.py on auth.connect (attempts disk restore)
"""

from __future__ import annotations

from pathlib import Path

from loguru import logger


# Base directory for all replay persistence
REPLAY_BASE_DIR = Path.home() / ".mobileflow" / "replay"


def get_replay_path(stable_id: str) -> Path:
    """Get the disk persistence directory for a given scope identity.

    Args:
        stable_id: The stable identity string (e.g. hashed session_token
            for LAN, hashed bearer_token for Tunnel).

    Returns:
        Path to the replay directory for this scope.
        Directory may not exist yet (created on first push).
    """
    # Use first 32 chars of stable_id as directory name to avoid
    # filesystem issues with very long hash strings
    dir_name = stable_id[:32]
    return REPLAY_BASE_DIR / dir_name


def has_persisted_replay(stable_id: str) -> bool:
    """Check if disk replay data exists for a given scope identity.

    Used during auth.connect to determine if a StreamReplay can be
    restored from a previous Agent run.

    Args:
        stable_id: The stable identity string.

    Returns:
        True if replay files exist on disk.
    """
    replay_path = get_replay_path(stable_id)
    meta_file = replay_path / "turn_meta.json"
    replay_file = replay_path / "current_turn.jsonl"
    return meta_file.exists() or replay_file.exists()


def cleanup_replay_dir(stable_id: str) -> None:
    """Remove all replay files for a given scope identity.

    Called when:
    - Scope is explicitly disposed (LRU eviction, user disconnect with grace=0)
    - User starts a completely new session (old replay no longer relevant)

    Args:
        stable_id: The stable identity string.
    """
    replay_path = get_replay_path(stable_id)
    if not replay_path.exists():
        return
    try:
        for f in replay_path.iterdir():
            f.unlink(missing_ok=True)
        replay_path.rmdir()
        logger.debug(f"已清理 replay 目录: stable_id={stable_id[:16]}")
    except Exception as e:
        logger.warning(f"replay 目录清理失败: stable_id={stable_id[:16]}, {e}")
