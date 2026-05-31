"""Daemon exclusive lock file.

Prevents multiple daemon instances from running simultaneously.
Uses platform-specific file locking (``fcntl.flock`` on Unix,
``msvcrt.locking`` on Windows).

Reference: Happy ``daemon/run.ts`` ``acquireDaemonLock``.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Optional

from loguru import logger


class DaemonLock:
    """Cross-platform exclusive file lock for the daemon process.

    Attributes:
        _lock_file: Path to the lock file.
        _fd: Open file descriptor (held while the lock is active).
    """

    def __init__(self, data_dir: Path):
        self._lock_file = data_dir / "daemon.lock"
        self._fd: Optional[int] = None

    def acquire(self) -> bool:
        """Attempt to acquire the exclusive lock.

        Returns:
            True if the lock was acquired, False if another daemon holds it.
        """
        try:
            self._lock_file.parent.mkdir(parents=True, exist_ok=True)
            self._fd = os.open(
                str(self._lock_file),
                os.O_CREAT | os.O_RDWR,
            )

            if sys.platform == "win32":
                import msvcrt
                try:
                    msvcrt.locking(self._fd, msvcrt.LK_NBLCK, 1)
                    logger.info("独占锁获取成功 (Windows)")
                    return True
                except OSError:
                    os.close(self._fd)
                    self._fd = None
                    logger.warning("独占锁获取失败: 已被其他进程持有 (Windows)")
                    return False
            else:
                import fcntl
                try:
                    fcntl.flock(self._fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    logger.info("独占锁获取成功 (Unix)")
                    return True
                except OSError:
                    os.close(self._fd)
                    self._fd = None
                    logger.warning("独占锁获取失败: 已被其他进程持有 (Unix)")
                    return False

        except Exception as e:
            logger.error(f"获取锁失败: {e}")
            return False

    def release(self) -> None:
        """Release the exclusive lock and delete the lock file."""
        if self._fd is not None:
            try:
                if sys.platform == "win32":
                    import msvcrt
                    try:
                        msvcrt.locking(self._fd, msvcrt.LK_UNLCK, 1)
                    except OSError:
                        pass
                else:
                    import fcntl
                    fcntl.flock(self._fd, fcntl.LOCK_UN)
                os.close(self._fd)
            except Exception:
                pass
            self._fd = None
            logger.debug("独占锁已释放")

        # Remove the lock file
        try:
            self._lock_file.unlink(missing_ok=True)
        except OSError:
            pass
