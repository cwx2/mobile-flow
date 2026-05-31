"""Daemon state file management.

Persists daemon runtime state to ``~/.mobileflow/daemon.state.json``.
Schema: ``{ pid, http_port, start_time, version, last_heartbeat,
relay_connected, paired_devices }``.

Reference: Happy ``daemon/run.ts`` ``DaemonLocallyPersistedState``.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Optional

from loguru import logger

from ..utils.json_file import load_json_file


def read_daemon_state(data_dir: Path) -> Optional[dict[str, Any]]:
    """Read the daemon state file.

    Args:
        data_dir: Path to the data directory containing the state file.

    Returns:
        Parsed state dict, or None if the file does not exist or is invalid.
    """
    state_file = data_dir / "daemon.state.json"
    data = load_json_file(state_file)
    if data:
        logger.debug(f"Daemon 状态已读取: pid={data.get('pid')}")
    return data


def write_daemon_state(data_dir: Path, state: dict[str, Any]) -> None:
    """Write the daemon state file.

    Args:
        data_dir: Path to the data directory.
        state: State dict to persist.
    """
    data_dir.mkdir(parents=True, exist_ok=True)
    state_file = data_dir / "daemon.state.json"
    state_file.write_text(
        json.dumps(state, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    logger.debug(f"Daemon 状态已写入: pid={state.get('pid')}")


def delete_daemon_state(data_dir: Path) -> None:
    """Delete the daemon state file.

    Args:
        data_dir: Path to the data directory.
    """
    state_file = data_dir / "daemon.state.json"
    if state_file.exists():
        state_file.unlink()
        logger.debug("Daemon 状态文件已删除")
