"""Process management utilities.

Module: utils/
Responsibility:
    Cross-platform process lifecycle management. Provides graceful termination
    (SIGTERM → wait → SIGKILL) and process tree killing for all child processes.

    On Windows, uses Job Objects to bind child processes — when the Job handle
    is closed (or the parent exits), all processes in the Job are terminated
    automatically. This prevents zombie/orphan processes even if the parent
    crashes without cleanup.

    On Unix, uses process groups (start_new_session=True) and os.killpg to
    kill the entire process tree.

Used by:
    - terminal/pty_pipe.py, pty_wsl.py (terminal PTY cleanup)
    - providers/terminal_auth.py (auth process cleanup)
    - providers/acp_provider.py (ACP CLI process shutdown)
    - providers/acp_client.py (ACP client process cleanup)
    - services/file_service.py (ripgrep process cancellation)
    - services/command_executor.py (test panel script/preview processes)
"""

from __future__ import annotations

import asyncio
import subprocess
import sys

from loguru import logger


# ── Windows Job Object ──
# Binds child processes so they are automatically killed when the Job
# handle is closed (including parent crash). This is the standard pattern
# used by VS Code, Chrome, and other professional software on Windows.

_win_job_handle = None


def _get_win_job() -> object | None:
    """Get or create the Windows Job Object for child process management.

    Creates a Job Object with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE flag.
    All child processes assigned to this Job will be terminated when:
    - The Job handle is explicitly closed
    - The Agent process exits (handle auto-closed by OS)
    - The Agent crashes (handle auto-closed by OS)

    Returns:
        The Job handle, or None if creation fails (non-Windows or API error).
    """
    global _win_job_handle
    if sys.platform != "win32":
        return None
    if _win_job_handle is not None:
        return _win_job_handle

    try:
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.windll.kernel32

        # Create an anonymous Job Object
        handle = kernel32.CreateJobObjectW(None, None)
        if not handle:
            logger.warning("Windows Job Object 创建失败")
            return None

        # Set JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        # This ensures all processes in the Job are killed when the handle closes
        class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
            _fields_ = [
                ("PerProcessUserTimeLimit", ctypes.c_int64),
                ("PerJobUserTimeLimit", ctypes.c_int64),
                ("LimitFlags", wintypes.DWORD),
                ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t),
                ("ActiveProcessLimit", wintypes.DWORD),
                ("Affinity", ctypes.POINTER(ctypes.c_ulong)),
                ("PriorityClass", wintypes.DWORD),
                ("SchedulingClass", wintypes.DWORD),
            ]

        class IO_COUNTERS(ctypes.Structure):
            _fields_ = [
                ("ReadOperationCount", ctypes.c_uint64),
                ("WriteOperationCount", ctypes.c_uint64),
                ("OtherOperationCount", ctypes.c_uint64),
                ("ReadTransferCount", ctypes.c_uint64),
                ("WriteTransferCount", ctypes.c_uint64),
                ("OtherTransferCount", ctypes.c_uint64),
            ]

        class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
            _fields_ = [
                ("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
                ("IoInfo", IO_COUNTERS),
                ("ProcessMemoryLimit", ctypes.c_size_t),
                ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t),
                ("PeakJobMemoryUsed", ctypes.c_size_t),
            ]

        # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
        info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        info.BasicLimitInformation.LimitFlags = 0x2000

        # JobObjectExtendedLimitInformation = 9
        result = kernel32.SetInformationJobObject(
            handle, 9, ctypes.byref(info), ctypes.sizeof(info)
        )
        if not result:
            logger.warning("Windows Job Object 配置失败")
            kernel32.CloseHandle(handle)
            return None

        _win_job_handle = handle
        logger.debug("Windows Job Object 已创建 (KILL_ON_JOB_CLOSE)")
        return handle

    except Exception as e:
        logger.debug(f"Windows Job Object 初始化失败（可忽略）: {e}")
        return None


def assign_to_job(pid: int) -> bool:
    """Bind a child process to the Agent's lifecycle for automatic cleanup.

    Cross-platform mechanism to ensure child processes are terminated
    when the Agent exits (including crashes):

    - Windows: Assigns the process to a Job Object with
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE. When the Agent exits, the OS
      closes the Job handle and kills all processes in the Job.
    - Linux: No-op here. Linux uses start_new_session=True (set by the
      caller) + prctl(PR_SET_PDEATHSIG) via preexec_fn for kernel-level
      parent-death signaling. See get_subprocess_preexec_fn().
    - macOS: No-op here. macOS lacks prctl. Relies on start_new_session
      + explicit cleanup in scope.on_dispose(). Agent crash leaves orphans
      but launchd-managed Agents will be restarted and can clean up.

    Args:
        pid: Process ID to bind to the Agent's lifecycle.

    Returns:
        True if binding succeeded (or not applicable on this platform).
        False if binding failed on Windows.
    """
    if sys.platform != "win32":
        return True

    job = _get_win_job()
    if job is None:
        return False

    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32

        # PROCESS_SET_QUOTA | PROCESS_TERMINATE = 0x0100 | 0x0001
        proc_handle = kernel32.OpenProcess(0x0101, False, pid)
        if not proc_handle:
            logger.debug(f"无法打开进程 {pid} 用于 Job 分配")
            return False

        result = kernel32.AssignProcessToJobObject(job, proc_handle)
        kernel32.CloseHandle(proc_handle)

        if result:
            logger.debug(f"进程已加入 Job Object: pid={pid}")
            return True
        else:
            # Error 5 (ACCESS_DENIED) means process is already in a Job
            error = ctypes.get_last_error()
            if error == 5:
                logger.debug(f"进程已在其他 Job 中（可忽略）: pid={pid}")
                return True
            logger.debug(f"Job 分配失败: pid={pid}, error={error}")
            return False

    except Exception as e:
        logger.debug(f"Job 分配异常（可忽略）: pid={pid}, error={e}")
        return False


def get_subprocess_preexec_fn():
    """Get a preexec_fn for subprocess creation that binds child lifecycle.

    Returns a callable suitable for asyncio.create_subprocess_*'s preexec_fn
    parameter. On Linux, sets PR_SET_PDEATHSIG so the kernel sends SIGTERM
    to the child when the parent (Agent) dies. On other platforms, returns None.

    Usage:
        proc = await asyncio.create_subprocess_shell(
            cmd,
            preexec_fn=get_subprocess_preexec_fn(),
            start_new_session=True,  # Always set on Unix
        )

    Returns:
        A callable for preexec_fn on Linux, None on other platforms.
    """
    if sys.platform == "linux":
        def _set_pdeathsig():
            """Set PR_SET_PDEATHSIG to SIGTERM on Linux.

            Called in the child process after fork() but before exec().
            Tells the kernel to send SIGTERM to this process when its
            parent dies, preventing orphan processes.
            """
            import ctypes
            import signal
            # PR_SET_PDEATHSIG = 1
            libc = ctypes.CDLL("libc.so.6", use_errno=True)
            libc.prctl(1, signal.SIGTERM)
        return _set_pdeathsig
    return None


def is_process_alive(pid: int, timeout: float = 3) -> bool:
    """Check whether a process with the given PID is still running.

    Cross-platform: uses os.kill(pid, 0) on Unix, tasklist on Windows.
    Safe to call on any PID — returns False for non-existent processes.

    Args:
        pid: Process ID to check.
        timeout: Timeout in seconds for the tasklist subprocess (Windows only).

    Returns:
        True if the process exists and is running.
    """
    try:
        if sys.platform == "win32":
            # os.kill(pid, 0) doesn't work reliably on Windows
            result = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
                capture_output=True, text=True, timeout=timeout,
            )
            return str(pid) in result.stdout
        else:
            import os
            os.kill(pid, 0)
            return True
    except (ProcessLookupError, PermissionError):
        return False
    except Exception as e:
        logger.debug(f"进程存活检查异常: pid={pid}, error={e}")
        return False


def kill_process_tree_sync(pid: int, timeout: float = 5) -> None:
    """Kill a process and all its children (synchronous version).

    On Windows: uses ``taskkill /F /T /PID`` to kill the entire tree.
    On Unix: uses ``os.killpg`` to send SIGTERM to the process group,
    falling back to SIGKILL on the individual process.

    After killing, verifies the process is actually dead. If not, retries
    with SIGKILL as a last resort.

    Safe to call on already-dead processes.

    Args:
        pid: Process ID to kill.
        timeout: Timeout in seconds for the taskkill subprocess (Windows only).
    """
    try:
        if sys.platform == "win32":
            result = subprocess.run(
                ["taskkill", "/F", "/T", "/PID", str(pid)],
                capture_output=True, text=True, timeout=timeout,
            )
            if result.returncode != 0 and is_process_alive(pid):
                logger.warning(f"taskkill 失败 (rc={result.returncode}), 尝试直接 kill: pid={pid}")
                import os
                try:
                    os.kill(pid, 9)
                except (ProcessLookupError, PermissionError, OSError):
                    pass
        else:
            import os
            import signal
            try:
                os.killpg(os.getpgid(pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    except ProcessLookupError:
        pass  # Already dead
    except Exception as e:
        logger.debug(f"进程树清理出错（可忽略）: pid={pid}, error={e}")


async def kill_process_tree(proc: asyncio.subprocess.Process, timeout: float = 3) -> None:
    """Kill a subprocess and all its children, then wait for cleanup.

    Async wrapper around kill_process_tree_sync that also awaits the
    process to be reaped (prevents zombie processes on Unix).

    Safe to call on already-exited processes.

    Args:
        proc: The asyncio subprocess to kill.
        timeout: Seconds to wait for the process to be reaped after killing.
    """
    if proc.returncode is not None:
        return  # Already exited

    kill_process_tree_sync(proc.pid)

    # Wait briefly for the process to be reaped
    try:
        await asyncio.wait_for(proc.wait(), timeout=timeout)
    except asyncio.TimeoutError:
        # Last resort: direct kill
        try:
            proc.kill()
        except ProcessLookupError:
            pass


async def graceful_terminate(
    proc: asyncio.subprocess.Process,
    timeout: float = 5.0,
    label: str = "",
) -> bool:
    """Gracefully terminate a subprocess: SIGTERM → wait → force kill.

    Three-phase shutdown:
    1. Send SIGTERM (or terminate() on Windows) to give the process a
       chance to clean up.
    2. Wait up to ``timeout`` seconds for the process to exit.
    3. If still alive, force-kill the entire process tree.

    Always verifies the process is dead before returning. Never raises.

    Args:
        proc: The asyncio subprocess to terminate.
        timeout: Seconds to wait after SIGTERM before force-killing.
        label: Human-readable label for log messages (e.g. "ACP claude").

    Returns:
        True if the process exited (gracefully or forced), False if it
        somehow survived (should never happen, but logged as error).
    """
    tag = f"[{label}] " if label else ""

    if proc.returncode is not None:
        logger.debug(f"{tag}进程已退出: rc={proc.returncode}")
        return True

    pid = proc.pid

    # Phase 1: graceful SIGTERM
    try:
        proc.terminate()
        logger.debug(f"{tag}已发送 SIGTERM: pid={pid}")
    except ProcessLookupError:
        return True
    except Exception as e:
        logger.debug(f"{tag}SIGTERM 出错（可忽略）: {e}")

    # Phase 2: wait for graceful exit
    try:
        await asyncio.wait_for(proc.wait(), timeout=timeout)
        logger.debug(f"{tag}进程已优雅退出: pid={pid}, rc={proc.returncode}")
        return True
    except asyncio.TimeoutError:
        logger.warning(f"{tag}进程未在 {timeout}s 内退出，强制终止: pid={pid}")

    # Phase 3: force kill entire process tree
    await kill_process_tree(proc)

    # Verify death
    if is_process_alive(pid):
        logger.error(f"{tag}进程仍然存活（异常）: pid={pid}")
        return False

    logger.info(f"{tag}进程已强制终止: pid={pid}")
    return True
