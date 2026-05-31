"""
Terminal auth handler for ACP terminal-type authentication.

Executes the CLI's auth command (e.g. ``codex login --device-auth``),
parses stdout for Device Code URL and code, and reports results back
to the caller for forwarding to the mobile app.

Design:
  - Suppresses browser popup via BROWSER=echo env var
  - Parses stdout line-by-line with regex for URL + code patterns
  - Three-layer code extraction: same-line → cross-line lookahead → standalone fallback
  - Supports multiple CLI output formats (Codex, Claude, Gemini, etc.)
  - Progressive push: URL-only first, then full info when code arrives
  - Timeout from config (auth_device_code_timeout, default 600s)

Auth success is NOT determined by stdout content. The caller (terminal_auth_helper)
verifies auth via ACP probe — the only reliable method. stdout parsing is used
solely for device code extraction.
"""

from __future__ import annotations

import asyncio
import re
import sys
from dataclasses import dataclass, field
from typing import Callable, Optional

from loguru import logger

from ..utils.command import which
from ..utils.strings import strip_ansi


@dataclass
class DeviceCodeInfo:
    """Parsed device code information from CLI stdout.

    Attributes:
        url: Verification URL the user should open (e.g. https://www.openai.com/device).
        code: Short device code to enter (e.g. ABCD-EFGH).
        raw_output: Full stdout captured from the CLI process.
    """
    url: str = ""
    code: str = ""
    raw_output: str = ""


# Regex patterns for extracting URL and device code from CLI stdout.
_URL_PATTERNS = [
    re.compile(r'(https?://\S+/device\S*)', re.IGNORECASE),
    re.compile(r'(?:url|URL|link|open|visit|navigate)\s*[:：]?\s*(https?://\S+)', re.IGNORECASE),
    re.compile(r'(https?://\S+)', re.IGNORECASE),
]

# Same-line patterns: keyword + code on the same line.
# These require "code" (or variant) immediately before the value.
_CODE_PATTERNS_WITH_KEYWORD = [
    # Priority 1: XXXX-XXXX with dash separator (Codex, GitHub, most OAuth)
    re.compile(r'(?:code|Code|CODE)\s*[:：]?\s*([A-Z0-9]{4,}-[A-Z0-9]{4,})', re.IGNORECASE),
    # Priority 2: All-uppercase alphanumeric 6-12 chars (Azure CLI style)
    # Case-sensitive to avoid matching English words like "authorization"
    re.compile(r'(?:code|Code|CODE)\s*[:：]?\s*([A-Z0-9]{6,12})\b'),
    # Priority 3: Mixed-case but must contain at least one digit
    # Lookahead ensures it's not a pure English word
    re.compile(
        r'(?:code|Code|CODE)\s*[:：]?\s*'
        r'((?=[A-Za-z0-9]*\d)[A-Za-z0-9]{6,12})\b',
        re.IGNORECASE,
    ),
]

# Standalone patterns: code on its own line (no keyword needed).
# Used for cross-line lookahead and standalone fallback.
_CODE_PATTERNS_STANDALONE = [
    # XXXX-XXXX on a line by itself
    re.compile(r'^\s*([A-Z0-9]{4,}-[A-Z0-9]{4,})\s*$', re.IGNORECASE),
    # All-uppercase 6-12 chars on a line by itself (case-sensitive)
    re.compile(r'^\s*([A-Z0-9]{6,12})\s*$'),
]

# Keyword hint: line mentions "code" in a natural-language phrase but the
# actual value may appear on the next line (e.g. "Enter this code:\n ABCD-EFGH").
_CODE_KEYWORD_HINT = re.compile(
    r'\b(?:one-time\s+code|verification\s+code|device\s+code|'
    r'authorization\s+code|auth\s+code|enter\s+(?:this\s+)?code|'
    r'your\s+code)\b',
    re.IGNORECASE,
)

# How many subsequent lines to scan after a keyword hint
_CODE_LOOKAHEAD_LINES = 3


def _clean_url(raw_url: str) -> str:
    """Clean a URL extracted from CLI output.

    Strips residual ANSI codes, trailing punctuation, and terminal
    artifacts captured by greedy ``\\S+`` regex patterns.

    Args:
        raw_url: Raw URL string from regex match.

    Returns:
        Cleaned URL, or empty string if invalid.
    """
    url = strip_ansi(raw_url)
    url = url.rstrip('.,;:)]\'">')
    if not url.startswith(('http://', 'https://')):
        return ''
    return url


def _parse_device_code(output: str) -> DeviceCodeInfo:
    """Parse CLI stdout to extract device code URL and code.

    Uses a three-layer strategy to handle diverse CLI output formats:

    Layer 1 – Same-line keyword match:
        Scan each line for "code: XXXX-XXXX" style patterns where the
        keyword and value appear on the same line.

    Layer 2 – Cross-line lookahead:
        When a line contains a keyword hint (e.g. "Enter this code") but
        no value, look ahead up to ``_CODE_LOOKAHEAD_LINES`` subsequent
        lines for a standalone code pattern.

    Layer 3 – Standalone fallback:
        If a URL was already found but no code matched via Layer 1/2,
        accept a standalone XXXX-XXXX pattern anywhere in the output.
        This handles CLIs that print the code on its own line without
        any keyword.

    Args:
        output: Full stdout text from the CLI auth process.

    Returns:
        DeviceCodeInfo with extracted url/code (may be empty if not found).
    """
    clean = strip_ansi(output)
    info = DeviceCodeInfo(raw_output=output)
    lines = clean.splitlines()

    # Extract URL (try patterns in priority order)
    for pattern in _URL_PATTERNS:
        match = pattern.search(clean)
        if match:
            info.url = _clean_url(match.group(1))
            if info.url:
                break

    # Layer 1: same-line keyword match (line by line)
    for line in lines:
        for pattern in _CODE_PATTERNS_WITH_KEYWORD:
            match = pattern.search(line)
            if match:
                info.code = match.group(1)
                logger.debug(f"Device Code 解析 Layer1 命中: code={info.code!r}")
                logger.debug(f"Device Code 解析结果: url={info.url!r}, code={info.code!r}")
                return info

    # Layer 2: cross-line lookahead (keyword on line N, code on N+1..N+3)
    for i, line in enumerate(lines):
        if _CODE_KEYWORD_HINT.search(line):
            # Keyword hint found — scan the next few lines for standalone code
            for j in range(i + 1, min(i + 1 + _CODE_LOOKAHEAD_LINES, len(lines))):
                for pattern in _CODE_PATTERNS_STANDALONE:
                    match = pattern.search(lines[j])
                    if match:
                        info.code = match.group(1)
                        logger.debug(
                            f"Device Code 解析 Layer2 命中: "
                            f"hint_line={i}, code_line={j}, code={info.code!r}"
                        )
                        logger.debug(f"Device Code 解析结果: url={info.url!r}, code={info.code!r}")
                        return info

    # Layer 3: standalone fallback — only when URL already found
    # Accept XXXX-XXXX anywhere in output (no keyword required)
    if info.url:
        for line in lines:
            for pattern in _CODE_PATTERNS_STANDALONE:
                match = pattern.search(line)
                if match:
                    info.code = match.group(1)
                    logger.debug(f"Device Code 解析 Layer3 fallback 命中: code={info.code!r}")
                    logger.debug(f"Device Code 解析结果: url={info.url!r}, code={info.code!r}")
                    return info

    logger.debug(f"Device Code 解析结果: url={info.url!r}, code={info.code!r}")
    return info



@dataclass
class TerminalAuthHandle:
    """Handle returned by run_terminal_auth for process lifecycle management.

    The caller uses this to:
    1. Access the parsed device code info (url, code).
    2. Check if the process exited and its exit code.
    3. Kill the CLI process when auth is confirmed by ACP probe.

    Auth success is NOT determined here — the caller verifies via ACP probe.
    This handle only manages the CLI process lifecycle and device code extraction.

    Attributes:
        proc: The subprocess handle (for kill/wait).
        info: Parsed device code info (url, code, raw_output).
        process_exited: True if the CLI process exited on its own.
        exit_code: Process return code (None if still running).
    """
    proc: asyncio.subprocess.Process
    info: DeviceCodeInfo
    process_exited: bool = False
    exit_code: int | None = None

    async def kill(self):
        """Kill the CLI process and its entire process tree.

        Uses the shared kill_process_tree utility which handles Windows
        (taskkill /T) and Unix (os.killpg) correctly.

        Safe to call multiple times.
        """
        from ..utils.process import kill_process_tree
        await kill_process_tree(self.proc)


async def run_terminal_auth(
    command: str,
    args: list[str],
    timeout: float = 600,
    execution_env: str = "native",
    on_device_code: Optional[Callable] = None,
) -> TerminalAuthHandle:
    """Execute a CLI terminal auth command and extract device code info.

    Runs the CLI auth process (e.g. ``claude login``), reads stdout
    line-by-line, and extracts the device code URL and code using a
    three-layer parsing strategy. The extracted info is pushed to the
    frontend progressively via the on_device_code callback.

    This function does NOT determine whether auth succeeded — that is
    the caller's responsibility via ACP probe (the only reliable method).
    stdout content is used solely for device code extraction.

    Returns a TerminalAuthHandle so the caller can manage the process
    lifecycle (kill it when auth is confirmed by ACP probe).

    Args:
        command: CLI executable name (e.g. "codex", "claude").
        args: Auth command arguments (e.g. ["login", "--device-auth"]).
        timeout: Max seconds to wait for stdout activity. Defaults to 600.
        execution_env: "native" or "wsl".
        on_device_code: Optional async callback ``(DeviceCodeInfo) -> None``,
            called progressively: first with URL-only, then with full URL+code.

    Returns:
        TerminalAuthHandle with process handle, parsed info, and exit status.
    """
    # Resolve command path
    resolved = which(command) or command

    # Build environment: suppress browser popup
    import os
    env = dict(os.environ)
    if sys.platform == "win32":
        env["BROWSER"] = "cmd /c echo"
    else:
        env["BROWSER"] = "echo"
    # Suppress CLI color output to avoid ANSI codes in parsed stdout
    env["NO_COLOR"] = "1"
    env["TERM"] = "dumb"
    env.pop("FORCE_COLOR", None)

    # Build command line
    if execution_env == "wsl":
        from ..utils.path import win_to_wsl
        inner = f'BROWSER=echo {command} {" ".join(args)}'
        cmd_parts = ["wsl", "bash", "-lc", inner]
    else:
        if sys.platform == "win32" and resolved.lower().endswith((".cmd", ".bat")):
            cmd_parts = ["cmd", "/c", resolved, *args]
        else:
            cmd_parts = [resolved, *args]

    logger.info(f"启动 terminal 认证: {' '.join(cmd_parts)}")

    proc = await asyncio.create_subprocess_exec(
        *cmd_parts,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        env=env,
    )

    # Read stdout line-by-line, accumulate output
    output_lines: list[str] = []
    info = DeviceCodeInfo()
    handle = TerminalAuthHandle(proc=proc, info=info)
    notified = False  # Track whether on_device_code has been called with full info
    url_only_pushed = False  # Track whether URL-only push has been sent

    async def _read_output():
        """Read stdout line-by-line, extract device code info.

        Returns when the process closes stdout (exits) or timeout is reached.
        Does NOT detect auth success — that's the caller's job via ACP probe.
        """
        nonlocal info, notified, url_only_pushed
        assert proc.stdout is not None

        # Cross-line lookahead state
        lookahead_remaining = 0

        while True:
            line_bytes = await proc.stdout.readline()
            if not line_bytes:
                # EOF — process closed stdout (likely exited)
                handle.process_exited = True
                handle.exit_code = proc.returncode
                logger.info(f"terminal 认证进程 stdout EOF: exit_code={proc.returncode}")
                break
            line = strip_ansi(line_bytes.decode("utf-8", errors="replace")).rstrip()
            output_lines.append(line)
            logger.debug(f"terminal auth stdout: {line}")

            # --- URL extraction ---
            if not info.url:
                for pattern in _URL_PATTERNS:
                    match = pattern.search(line)
                    if match:
                        info.url = _clean_url(match.group(1))
                        if info.url:
                            logger.info(f"Device Code URL 检测到: {info.url}")
                            break

            # --- Code extraction (three-layer strategy) ---
            if not info.code:
                code_found = False

                # Layer 1: same-line keyword match
                for pattern in _CODE_PATTERNS_WITH_KEYWORD:
                    match = pattern.search(line)
                    if match:
                        info.code = match.group(1)
                        code_found = True
                        logger.info(f"Device Code 检测到 (Layer1 同行): {info.code}")
                        break

                # Layer 2: cross-line lookahead
                if not code_found and lookahead_remaining > 0:
                    lookahead_remaining -= 1
                    for pattern in _CODE_PATTERNS_STANDALONE:
                        match = pattern.search(line)
                        if match:
                            info.code = match.group(1)
                            code_found = True
                            logger.info(f"Device Code 检测到 (Layer2 跨行): {info.code}")
                            break

                # Detect keyword hint to start lookahead for subsequent lines
                if not code_found and _CODE_KEYWORD_HINT.search(line):
                    lookahead_remaining = _CODE_LOOKAHEAD_LINES
                    logger.debug(f"Device Code 关键词提示检测到，启动 {_CODE_LOOKAHEAD_LINES} 行前瞻")

                # Layer 3: standalone fallback
                if not code_found and info.url:
                    for pattern in _CODE_PATTERNS_STANDALONE:
                        match = pattern.search(line)
                        if match:
                            info.code = match.group(1)
                            code_found = True
                            logger.info(f"Device Code 检测到 (Layer3 独立行): {info.code}")
                            break

            # --- Progressive push via on_device_code callback ---

            # Push URL-only as soon as URL is found but code is not yet available
            if info.url and not info.code and not url_only_pushed and on_device_code:
                url_only_pushed = True
                logger.info(f"Device Code URL 就绪，先推送 URL: url={info.url}")
                try:
                    await on_device_code(info)
                except Exception as e:
                    logger.warning(f"on_device_code URL-only 回调出错: {e}")

            # Push full info (URL + code) once both are available
            if info.url and info.code and not notified and on_device_code:
                notified = True
                logger.info(f"Device Code 就绪，通知前端: url={info.url}, code={info.code}")
                try:
                    await on_device_code(info)
                except Exception as e:
                    logger.warning(f"on_device_code 回调出错: {e}")

    try:
        await asyncio.wait_for(_read_output(), timeout=timeout)
    except asyncio.TimeoutError:
        logger.warning(f"terminal 认证 stdout 读取超时: {timeout}s")
        # Don't kill the process here — the caller manages lifecycle via handle

    # Capture final state
    info.raw_output = "\n".join(output_lines)
    handle.info = info

    # If process already exited, capture exit code
    if proc.returncode is not None:
        handle.process_exited = True
        handle.exit_code = proc.returncode
        if proc.returncode == 0:
            logger.info("terminal 认证进程正常退出: code=0")
        else:
            logger.warning(f"terminal 认证进程退出: code={proc.returncode}")

    # If we didn't get URL/code from line-by-line parsing, try full output
    if not info.url or not info.code:
        full_parse = _parse_device_code(info.raw_output)
        if not info.url and full_parse.url:
            info.url = full_parse.url
        if not info.code and full_parse.code:
            info.code = full_parse.code

    return handle
