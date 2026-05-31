"""
Terminal auth flow helper for CLIManager.

Orchestrates the terminal-type authentication flow:

1. Run the CLI auth process (e.g. ``claude login``) to extract device code
2. Push device code URL + code to the mobile app
3. Verify auth completion via ACP probe (the only reliable method)

Auth success is determined solely by ACP probe (list_sessions succeeds).
stdout content is used only for device code extraction, never for
success/failure judgment — this avoids false positives from ambiguous
CLI output like "Not logged in" containing "logged in".

Two concurrent verification paths:
- Process-triggered: when the CLI process exits, immediately do an ACP probe
- Polling: background ACP probe every N seconds (catches CLIs that hang)
The first successful probe wins.
"""

from __future__ import annotations

import asyncio
from typing import Callable, Coroutine

from loguru import logger

from ..providers.base import AgentProvider
from ..core.config import AgentConfig
from ..utils.i18n import t


async def _strategy_c_acp_probe(
    provider: AgentProvider,
    poll_interval: float,
    timeout: float,
    device_code_ready: asyncio.Event,
) -> bool:
    """Strategy C: Periodically probe ACP to check if auth is now valid.

    Waits until the device code has been pushed to the frontend before
    starting (no point probing before the user can even see the code).
    Then polls list_sessions() every ``poll_interval`` seconds. If the
    call succeeds without raising an auth error, auth is confirmed.

    This catches the scenario where the CLI process hangs silently after
    the user completes browser login — the ACP server already has valid
    credentials, but the CLI auth process doesn't know/care.

    Args:
        provider: The ACP provider instance (must have list_sessions).
        poll_interval: Seconds between probe attempts.
        timeout: Max seconds to keep probing.
        device_code_ready: Event set when device code has been pushed to frontend.

    Returns:
        True if ACP probe confirmed auth success, False on timeout.
    """
    # Wait until device code is pushed — no point probing before user can act
    try:
        await asyncio.wait_for(device_code_ready.wait(), timeout=60)
    except asyncio.TimeoutError:
        logger.debug("Strategy C: device code 未就绪，跳过 ACP 探测")
        return False

    # Give the user a few seconds to start the browser login before probing
    await asyncio.sleep(poll_interval)

    logger.info(f"Strategy C: 启动 ACP 认证探测，间隔={poll_interval}s")
    elapsed = 0.0
    attempt = 0

    while elapsed < timeout:
        attempt += 1
        try:
            # Try to re-initialize the provider. If auth is valid,
            # initialize() will succeed. We can't use list_sessions()
            # because it silently returns [] when capabilities are unknown.
            cwd = getattr(provider, '_work_dir', '') or '.'
            await asyncio.wait_for(
                provider.initialize(cwd), timeout=10,
            )
            logger.info(
                f"Strategy C: ACP 探测成功 (attempt={attempt}), 认证已生效"
            )
            return True
        except asyncio.TimeoutError:
            logger.debug(f"Strategy C: ACP 探测超时 (attempt={attempt})")
        except Exception as e:
            logger.debug(f"Strategy C: ACP 探测失败 (attempt={attempt}): {e}")

        await asyncio.sleep(poll_interval)
        elapsed += poll_interval

    logger.warning(f"Strategy C: ACP 探测超时，已尝试 {attempt} 次")
    return False


async def _verify_auth_via_acp(provider: AgentProvider, timeout: float = 15) -> bool:
    """Verify auth by attempting to re-initialize the ACP provider.

    The most reliable way to check if auth succeeded: try to establish
    an ACP connection. If initialize() completes without error, the CLI
    has valid credentials. If it fails or times out, auth is still pending.

    We can't use list_sessions() because it silently returns [] when
    capabilities are unknown (which is the case after init timeout).

    Args:
        provider: The ACP provider instance.
        timeout: Max seconds for the init attempt.

    Returns:
        True if ACP initialize succeeded, False otherwise.
    """
    try:
        # Re-initialize: if auth is valid, this will succeed quickly
        cwd = getattr(provider, '_work_dir', '') or '.'
        await asyncio.wait_for(provider.initialize(cwd), timeout=timeout)
        return True
    except asyncio.TimeoutError:
        logger.debug("ACP 认证验证: initialize 超时")
        return False
    except Exception as e:
        logger.debug(f"ACP 认证验证: initialize 失败: {e}")
        return False


async def run_terminal_auth_flow(
    key: tuple[str, str],
    cli_name: str,
    provider: AgentProvider,
    method: dict,
    config: AgentConfig,
    push_status: Callable[..., Coroutine],
    command_override: str | None = None,
) -> bool:
    """Execute the full terminal auth flow with ACP-probe verification.

    Two concurrent paths race to confirm auth:

    Path 1 (process-triggered):
        Run the CLI auth process, extract device code, push to frontend.
        When the process exits, immediately do an ACP probe to verify.

    Path 2 (polling):
        Background loop calls list_sessions() every N seconds.
        Catches CLIs that hang silently after auth completes in browser.

    The first successful ACP probe wins. The CLI process is killed
    when auth is confirmed (no zombie processes).

    Auth success is NEVER determined by stdout content — only by ACP probe.

    Args:
        key: (client_id, cli_name) tuple.
        cli_name: CLI adapter name.
        provider: The ACP provider instance.
        method: Auth method dict with "args" field.
        config: Agent configuration (for timeouts).
        push_status: Async callback to push cli.status to frontend.
        command_override: If provided, use this as the CLI command.

    Returns:
        True if auth completed successfully (ACP probe confirmed).
        False on timeout or failure.
    """
    from ..providers.terminal_auth import run_terminal_auth

    args = method.get("args", [])
    if not args:
        logger.warning(f"terminal 认证无 args: {cli_name}")
        return False

    command = command_override or getattr(provider, '_command', '')
    execution_env = getattr(provider, '_execution_env', 'native')
    if not command:
        logger.warning(f"terminal 认证无 command: {cli_name}")
        return False

    timeout = config.lifecycle.auth_device_code_timeout
    poll_interval = config.lifecycle.auth_verification_poll_interval
    logger.info(
        f"启动 terminal 认证流程: cli={cli_name}, "
        f"command={command}, args={args}, timeout={timeout}s"
    )
    await push_status(key, "auth_required", t("backend.startingAuthFlow"))

    # Event: set when device code has been pushed to frontend.
    # ACP polling waits for this before starting probes.
    device_code_ready = asyncio.Event()

    async def _on_device_code(info):
        """Push device code to frontend as soon as it's parsed."""
        logger.info(f"推送 Device Code 到前端: url={info.url}, code={info.code}")
        provider._device_code_url = info.url  # type: ignore
        provider._device_code = info.code  # type: ignore
        provider._auth_type = "device_code"  # type: ignore
        await push_status(key, "auth_required", t("backend.completeLoginInBrowser"))
        if info.code:
            device_code_ready.set()

    # --- Path 1: Run CLI process, then ACP probe on exit ---
    async def _run_process_then_verify() -> bool:
        """Run the auth CLI process and verify via ACP probe when it exits."""
        handle = await run_terminal_auth(
            command=command,
            args=args,
            timeout=timeout,
            execution_env=execution_env,
            on_device_code=_on_device_code,
        )
        try:
            # Process has exited (or stdout timed out).
            # Regardless of exit code or stdout content, verify via ACP.
            if handle.process_exited:
                logger.info(
                    f"CLI 认证进程已退出: code={handle.exit_code}, "
                    f"尝试 ACP 探测确认认证状态"
                )
                if await _verify_auth_via_acp(provider):
                    logger.info(f"进程退出后 ACP 探测成功: cli={cli_name}")
                    return True
                # ACP probe failed after process exit — auth didn't work.
                # But don't return False yet if device code was pushed,
                # because the user might still be completing browser login.
                if handle.info.url or handle.info.code:
                    logger.info(
                        f"进程退出后 ACP 探测失败，但 device code 已推送，"
                        f"等待 ACP 轮询: cli={cli_name}"
                    )
                    return False  # Let polling path continue
                logger.warning(f"进程退出后 ACP 探测失败，无 device code: cli={cli_name}")
                return False
            else:
                # stdout timed out but process still running — let polling handle it
                logger.info(f"CLI 进程仍在运行，等待 ACP 轮询: cli={cli_name}")
                return False
        finally:
            await handle.kill()

    # --- Path 2: ACP polling (reuse existing Strategy C) ---
    # _strategy_c_acp_probe is already well-designed, keep it as-is.

    try:
        task_process = asyncio.create_task(
            _run_process_then_verify(), name="process_verify"
        )
        task_poll = asyncio.create_task(
            _strategy_c_acp_probe(provider, poll_interval, timeout, device_code_ready),
            name="acp_poll",
        )

        # Race both paths
        done, pending = await asyncio.wait(
            {task_process, task_poll},
            timeout=timeout,
            return_when=asyncio.FIRST_COMPLETED,
        )

        # Check if the first completed task succeeded
        success = False
        winning = None
        for task in done:
            try:
                if task.result():
                    success = True
                    winning = task.get_name()
                    break
            except Exception as e:
                logger.warning(f"认证路径异常: task={task.get_name()}, error={e}")

        if success:
            logger.info(f"认证成功 (winning={winning}): cli={cli_name}")
            for task in pending:
                task.cancel()
                try:
                    await task
                except (asyncio.CancelledError, Exception):
                    pass
            return True

        # First path returned False — wait for the other
        if pending:
            logger.info(f"第一个路径返回 False，等待剩余路径: cli={cli_name}")
            done2, pending2 = await asyncio.wait(
                pending, timeout=timeout, return_when=asyncio.FIRST_COMPLETED,
            )
            for task in done2:
                try:
                    if task.result():
                        winning = task.get_name()
                        logger.info(f"认证成功 (winning={winning}): cli={cli_name}")
                        for t in pending2:
                            t.cancel()
                            try:
                                await t
                            except (asyncio.CancelledError, Exception):
                                pass
                        return True
                except Exception as e:
                    logger.warning(f"认证路径异常: task={task.get_name()}, error={e}")
            for task in pending2:
                task.cancel()
                try:
                    await task
                except (asyncio.CancelledError, Exception):
                    pass

        logger.warning(f"所有认证路径均失败: cli={cli_name}")
        await push_status(key, "auth_required", t("backend.authTimeoutRetry", timeout=str(timeout)))
        return False

    except asyncio.CancelledError:
        logger.info(f"terminal 认证流程被取消: cli={cli_name}")
        return False
    except Exception as e:
        logger.error(f"terminal 认证出错: cli={cli_name}, error={e}")
        await push_status(key, "auth_required", t("backend.authError", error=str(e)))
        return False
