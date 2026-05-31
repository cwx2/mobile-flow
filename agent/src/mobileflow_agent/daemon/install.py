"""System service registration for auto-start on boot.

Supports three platforms:
    - macOS: launchd plist (``~/Library/LaunchAgents/``).
    - Linux: systemd user unit (``~/.config/systemd/user/``).
    - Windows: Task Scheduler (``schtasks``).

Reference: Happy ``daemon/install.ts`` + ``daemon/uninstall.ts``.
"""

from __future__ import annotations

import os
import sys
import subprocess
from pathlib import Path
from typing import Optional

from loguru import logger

from ..utils.encoding import decode_process_output


# launchd plist template (macOS)
_LAUNCHD_PLIST = """\
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.mobileflow.agent</string>
  <key>ProgramArguments</key>
  <array>
{program_arguments}
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>{log_path}/daemon.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>{log_path}/daemon.stderr.log</string>
  <key>WorkingDirectory</key>
  <string>{home_dir}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:{extra_path}</string>
  </dict>
</dict>
</plist>
"""

# systemd unit template (Linux)
_SYSTEMD_UNIT = """\
[Unit]
Description=MobileFlow Agent Daemon
After=network.target

[Service]
Type=simple
ExecStart={exec_start}
Restart=on-failure
RestartSec=5
WorkingDirectory={home_dir}
Environment=PATH=/usr/local/bin:/usr/bin:/bin:{extra_path}

[Install]
WantedBy=default.target
"""

_SERVICE_NAME_MACOS = "dev.mobileflow.agent"
_SERVICE_NAME_LINUX = "mobileflow-agent"
_TASK_NAME_WINDOWS = "MobileFlowAgent"


def _get_executable_command() -> tuple[str, list[str]]:
    """Detect whether running from PyInstaller bundle or Python source.

    Returns:
        A tuple of (executable_path, args) for launching the agent.
        Packaged: ("/path/to/mobileflow-agent", ["start", "--tray"])
        Source:   ("/path/to/python", ["-m", "mobileflow_agent", "start", "--tray"])
    """
    if getattr(sys, 'frozen', False):
        # Running from PyInstaller bundle
        return (sys.executable, ["start", "--tray"])
    else:
        # Running from Python source
        return (sys.executable, ["-m", "mobileflow_agent", "start", "--tray"])


def install_service(data_dir: Path) -> bool:
    """Register the daemon as a system service for auto-start on boot.

    Detects the current platform and generates the appropriate service
    configuration (launchd plist / systemd unit / Windows Task Scheduler).

    Args:
        data_dir: Path to the application data directory (used for log paths).

    Returns:
        True if the service was installed successfully.
    """
    logger.info(f"安装系统服务: platform={sys.platform}")
    platform = sys.platform

    if platform == "darwin":
        return _install_launchd(data_dir)
    elif platform == "linux":
        return _install_systemd(data_dir)
    elif platform == "win32":
        return _install_windows_task(data_dir)
    else:
        logger.error(f"不支持的平台: {platform}")
        return False


def uninstall_service() -> bool:
    """Remove the daemon system service.

    Returns:
        True if the service was uninstalled successfully.
    """
    logger.info("卸载系统服务...")
    platform = sys.platform

    if platform == "darwin":
        return _uninstall_launchd()
    elif platform == "linux":
        return _uninstall_systemd()
    elif platform == "win32":
        return _uninstall_windows_task()
    else:
        logger.error(f"不支持的平台: {platform}")
        return False


# ── macOS: launchd ──

def _install_launchd(data_dir: Path) -> bool:
    """Install a macOS launchd plist for auto-start.

    Args:
        data_dir: Application data directory (used for log paths).

    Returns:
        True on success.
    """
    plist_dir = Path.home() / "Library" / "LaunchAgents"
    plist_dir.mkdir(parents=True, exist_ok=True)
    plist_path = plist_dir / f"{_SERVICE_NAME_MACOS}.plist"

    log_dir = data_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    # Detect packaged vs source mode for correct launch command
    exe_path, exe_args = _get_executable_command()
    extra_path = str(Path(exe_path).parent)

    # Build launchd ProgramArguments XML entries
    all_args = [exe_path] + exe_args
    program_arguments = "\n".join(
        f"    <string>{arg}</string>" for arg in all_args
    )

    content = _LAUNCHD_PLIST.format(
        program_arguments=program_arguments,
        log_path=str(log_dir),
        home_dir=str(Path.home()),
        extra_path=extra_path,
    )

    plist_path.write_text(content, encoding="utf-8")
    logger.info(f"✅ launchd plist 已写入: {plist_path}")

    # Load the service
    try:
        subprocess.run(
            ["launchctl", "load", str(plist_path)],
            check=True, capture_output=True,
        )
        logger.info("✅ launchd 服务已加载")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"launchctl load 失败: {decode_process_output(e.stderr)}")
        return False


def _uninstall_launchd() -> bool:
    """Uninstall the macOS launchd plist.

    Returns:
        True if the plist was found and removed.
    """
    plist_path = Path.home() / "Library" / "LaunchAgents" / f"{_SERVICE_NAME_MACOS}.plist"

    if plist_path.exists():
        try:
            subprocess.run(
                ["launchctl", "unload", str(plist_path)],
                check=True, capture_output=True,
            )
        except subprocess.CalledProcessError:
            pass
        plist_path.unlink()
        logger.info("✅ launchd 服务已卸载")
        return True
    else:
        logger.info("launchd plist 不存在")
        return False


# ── Linux: systemd ──

def _install_systemd(data_dir: Path) -> bool:
    """Install a Linux systemd user unit for auto-start.

    Args:
        data_dir: Application data directory (unused, kept for API symmetry).

    Returns:
        True on success.
    """
    unit_dir = Path.home() / ".config" / "systemd" / "user"
    unit_dir.mkdir(parents=True, exist_ok=True)
    unit_path = unit_dir / f"{_SERVICE_NAME_LINUX}.service"

    # Detect packaged vs source mode for correct launch command
    exe_path, exe_args = _get_executable_command()
    exec_start = f"{exe_path} {' '.join(exe_args)}"
    extra_path = str(Path(exe_path).parent)

    content = _SYSTEMD_UNIT.format(
        exec_start=exec_start,
        home_dir=str(Path.home()),
        extra_path=extra_path,
    )

    unit_path.write_text(content, encoding="utf-8")
    logger.info(f"✅ systemd unit 已写入: {unit_path}")

    try:
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True, capture_output=True)
        subprocess.run(["systemctl", "--user", "enable", _SERVICE_NAME_LINUX], check=True, capture_output=True)
        subprocess.run(["systemctl", "--user", "start", _SERVICE_NAME_LINUX], check=True, capture_output=True)
        logger.info("✅ systemd 服务已启用并启动")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"systemctl 失败: {decode_process_output(e.stderr)}")
        return False


def _uninstall_systemd() -> bool:
    """Uninstall the Linux systemd user unit.

    Returns:
        True if the unit file was found and removed.
    """
    unit_path = Path.home() / ".config" / "systemd" / "user" / f"{_SERVICE_NAME_LINUX}.service"

    try:
        subprocess.run(["systemctl", "--user", "stop", _SERVICE_NAME_LINUX], capture_output=True)
        subprocess.run(["systemctl", "--user", "disable", _SERVICE_NAME_LINUX], capture_output=True)
    except Exception:
        pass

    if unit_path.exists():
        unit_path.unlink()
        try:
            subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
        except Exception:
            pass
        logger.info("✅ systemd 服务已卸载")
        return True
    else:
        logger.info("systemd unit 不存在")
        return False


# ── Windows: Task Scheduler ──

def _install_windows_task(data_dir: Path) -> bool:
    """Register a Windows Task Scheduler task for auto-start on logon.

    Args:
        data_dir: Application data directory (unused, kept for API symmetry).

    Returns:
        True on success.
    """
    # Detect packaged vs source mode for correct launch command
    exe_path, exe_args = _get_executable_command()
    command = f'"{exe_path}" {" ".join(exe_args)}'

    try:
        subprocess.run([
            "schtasks", "/Create",
            "/TN", _TASK_NAME_WINDOWS,
            "/TR", command,
            "/SC", "ONLOGON",
            "/RL", "LIMITED",
            "/F",  # Force overwrite
        ], check=True, capture_output=True)
        logger.info("✅ Windows 计划任务已创建")

        # Start immediately
        subprocess.run([
            "schtasks", "/Run", "/TN", _TASK_NAME_WINDOWS,
        ], check=True, capture_output=True)
        logger.info("✅ 任务已启动")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"schtasks 失败: {decode_process_output(e.stderr)}")
        return False


def _uninstall_windows_task() -> bool:
    """Remove the Windows Task Scheduler task.

    Returns:
        True if the task was found and deleted.
    """
    try:
        subprocess.run([
            "schtasks", "/Delete", "/TN", _TASK_NAME_WINDOWS, "/F",
        ], check=True, capture_output=True)
        logger.info("✅ Windows 计划任务已删除")
        return True
    except subprocess.CalledProcessError:
        logger.info("Windows 计划任务不存在")
        return False
