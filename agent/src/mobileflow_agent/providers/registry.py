"""
ProviderRegistry: ACP Agent factory and CLI detection.

Responsibilities:
  - Maintain built-in ACP CLI registry (16+ mainstream agents).
  - Auto-detect available CLIs (native PATH → WSL fallback).
  - One-click install via ``npm i -g``.
  - Custom agent CRUD (persisted to ~/.mobileflow/custom_agents.json).
  - Plugin agent injection/ejection.

Called by:
  - CLIManager: get provider instances by name.
  - WebSocketServer: CLI list, install, custom agent management.
"""

from __future__ import annotations

import asyncio
import platform
from typing import Optional

from loguru import logger

from .acp_provider import ACPProvider
from .base import AgentProvider
from ..utils.command import which
from ..utils.encoding import decode_process_output
from ..utils.i18n import t
from ..utils.response import R


def _detect_wsl() -> bool:
    """Detect whether WSL is available on the current system (Windows only)."""
    if platform.system() != "Windows":
        return False
    return which("wsl") is not None

# ── ACP CLI Registry (config-driven) ──

ACP_REGISTRY: dict[str, dict] = {
    # ── Anthropic ──
    "claude-code": {
        "command": "claude",
        "args": ["acp"],
        "display_name": "Claude Code",
        "install_packages": [
            {"package": "@anthropic-ai/claude-code", "label": "Claude Code CLI"},
        ],
        "install_hint": "npm i -g @anthropic-ai/claude-code",
        "terminal_cmd": "claude",
        "auth_command": ["claude", "auth", "login"],
    },
    # ── OpenAI ──
    "codex": {
        "command": "codex-acp",
        "args": [],
        "display_name": "Codex (ACP)",
        "install_packages": [
            {"package": "@openai/codex", "label": "Codex CLI"},
            {"package": "@zed-industries/codex-acp", "label": "ACP Adapter"},
        ],
        "install_hint": "npm i -g @openai/codex @zed-industries/codex-acp",
        "terminal_cmd": "codex",
        "auth_command": ["codex", "login", "--device-auth"],
    },
    # ── Google ──
    "gemini": {
        "command": "gemini",
        "args": ["--acp"],
        "display_name": "Gemini CLI",
        "install_packages": [
            {"package": "@google/gemini-cli", "label": "Gemini CLI"},
        ],
        "install_hint": "npm i -g @google/gemini-cli",
        "terminal_cmd": "gemini",
    },
    # ── GitHub ──
    "copilot": {
        "command": "copilot",
        "args": ["--acp"],
        "display_name": "GitHub Copilot",
        "install_packages": [
            {"package": "@github/copilot", "label": "GitHub Copilot CLI"},
        ],
        "install_hint": "npm i -g @github/copilot",
        "terminal_cmd": "copilot",
    },
    # ── Cline ──
    "cline": {
        "command": "cline",
        "args": ["--acp"],
        "display_name": "Cline",
        "install_packages": [
            {"package": "cline", "label": "Cline CLI"},
        ],
        "install_hint": "npm i -g cline",
        "terminal_cmd": "cline",
        "auth_command": ["cline", "auth"],
    },
    # ── Cursor ──
    "cursor": {
        "command": "cursor-agent",
        "args": ["acp"],
        "display_name": "Cursor",
        "install_hint": "Download Cursor IDE from cursor.com",
        "terminal_cmd": "cursor-agent",
    },
    # ── Alibaba Qwen ──
    "qwen-code": {
        "command": "qwen-code",
        "args": ["--acp"],
        "display_name": "Qwen Code",
        "install_packages": [
            {"package": "@qwen-code/qwen-code", "label": "Qwen Code CLI"},
        ],
        "install_hint": "npm i -g @qwen-code/qwen-code",
        "terminal_cmd": "qwen-code",
    },
    # ── Tencent Cloud ──
    "codebuddy": {
        "command": "codebuddy-code",
        "args": ["--acp"],
        "display_name": "CodeBuddy",
        "install_packages": [
            {"package": "@tencent-ai/codebuddy-code", "label": "CodeBuddy CLI"},
        ],
        "install_hint": "npm i -g @tencent-ai/codebuddy-code",
        "terminal_cmd": "codebuddy-code",
    },
    # ── Kilo ──
    "kilo": {
        "command": "kilo",
        "args": ["acp"],
        "display_name": "Kilo Code",
        "install_packages": [
            {"package": "@kilocode/cli", "label": "Kilo Code CLI"},
        ],
        "install_hint": "npm i -g @kilocode/cli",
        "terminal_cmd": "kilo",
    },
    # ── Augment Code ──
    "auggie": {
        "command": "auggie",
        "args": ["--acp"],
        "display_name": "Auggie",
        "install_packages": [
            {"package": "@augmentcode/auggie", "label": "Auggie CLI"},
        ],
        "install_hint": "npm i -g @augmentcode/auggie",
        "terminal_cmd": "auggie",
    },
    # ── AWS Kiro ──
    "kiro": {
        "command": "kiro-cli",
        "args": ["acp"],
        "display_name": "Kiro CLI",
        "install_hint": "Windows: irm 'https://cli.kiro.dev/install.ps1' | iex\nLinux/macOS: curl -fsSL https://cli.kiro.dev/install | bash",
        "terminal_cmd": "kiro-cli",
    },
}


class ProviderInfo:
    """Detected CLI information for the adapter list.

    Attributes:
        name: CLI identifier (e.g. "codex", "claude-code").
        display_name: Human-readable name shown in the App.
        available: Whether the CLI binary was found on the system.
        install_hint: Human-readable install instructions.
        install_packages: List of npm packages to install (empty = manual install only).
        is_custom: Whether this is a user-added custom agent.
        source: Origin of the CLI entry ("builtin", "custom", "plugin").
    """

    def __init__(self, name: str, display_name: str, available: bool,
                 install_hint: str = "", install_npm: str = "",
                 install_packages: list[dict] | None = None,
                 is_custom: bool = False, source: str = "builtin",
                 execution_env: str = "native"):
        self.name = name
        self.display_name = display_name
        self.available = available
        self.install_hint = install_hint
        # Backward compat: convert old install_npm string to install_packages list
        if install_packages:
            self.install_packages = install_packages
        elif install_npm:
            self.install_packages = [{"package": install_npm, "label": display_name}]
        else:
            self.install_packages = []
        self.is_custom = is_custom
        self.source = source
        self.execution_env = execution_env

    def to_dict(self) -> dict:
        d = {
            "name": self.name,
            "display_name": self.display_name,
            "protocol": "acp",
            "installed": self.available,
            "is_custom": self.is_custom,
            "source": self.source,
            "execution_env": self.execution_env,
            # App uses this to decide whether to show install/uninstall buttons
            "can_install": len(self.install_packages) > 0,
        }
        if not self.available:
            d["install_hint"] = self.install_hint
        return d


class ProviderRegistry:
    """Pure ACP factory: detect available CLIs and create ACPProvider instances.

    Detection strategy: native PATH check (instant) → WSL batch probe (parallel).
    Custom agents are loaded from ~/.mobileflow/custom_agents.json.
    """

    def __init__(self, event_bus=None, process_terminate_timeout: float = 5.0):
        self._detected: list[ProviderInfo] = []
        self._providers: dict[str, ACPProvider] = {}
        self._event_bus = event_bus
        self._has_wsl = _detect_wsl()
        self._process_terminate_timeout = process_terminate_timeout
        # Runtime overrides for execution_env. Populated when WSL fallback
        # triggers or when the user manually specifies an environment.
        # Takes priority over the detect_all probe result.
        self._env_overrides: dict[str, str] = {}

    async def detect_all(self) -> list[ProviderInfo]:
        """Detect all available ACP CLIs (built-in + custom).

        Probes native PATH first (instant), then WSL in a single batch process.
        Creates ACPProvider instances for available CLIs.

        Returns:
            List of ProviderInfo with availability status.
        """
        self._detected.clear()
        self._env_overrides.clear()
        logger.info("检测可用的 AI CLI...")

        # Merge built-in + custom
        all_agents = dict(ACP_REGISTRY)
        custom = self._load_custom_agents()
        for name, config in custom.items():
            if name not in all_agents:
                all_agents[name] = {**config, "_custom": True}

        # Probe all commands in parallel
        commands = {name: config["command"] for name, config in all_agents.items()}
        probe_results = await self._probe_all(commands)

        for name, config in all_agents.items():
            found_env = probe_results.get(name)
            is_custom = config.get("_custom", False)

            source = "custom" if is_custom else "builtin"

            if found_env:
                provider = ACPProvider(
                    command=config["command"],
                    args=config["args"],
                    execution_env=found_env,
                    display_name=config["display_name"],
                    event_bus=self._event_bus,
                    install_hint=config.get("install_hint", ""),
                    process_terminate_timeout=self._process_terminate_timeout,
                )
                self._providers[name] = provider
                self._detected.append(ProviderInfo(
                    name, config["display_name"], True,
                    install_packages=config.get("install_packages"),
                    is_custom=is_custom,
                    source=source,
                    execution_env=found_env,
                ))
                tag = f" [{found_env}]" if found_env != "native" else ""
                resolved_path = which(config["command"]) or config["command"]
                logger.info(f"  ✅ {config['display_name']} (ACP){tag} → {resolved_path}")
            else:
                self._detected.append(ProviderInfo(
                    name, config["display_name"], False,
                    install_hint=config.get("install_hint", ""),
                    install_packages=config.get("install_packages"),
                    is_custom=is_custom,
                    source=source,
                ))
                logger.debug(f"  ❌ {config['display_name']} (ACP)")

        available = [i.name for i in self._detected if i.available]
        logger.info(f"可用 CLI: {len(available)}/{len(all_agents)} — {', '.join(available) or '无'}")
        return self._detected

    async def _probe_all(self, commands: dict[str, str]) -> dict[str, str | None]:
        """Probe all commands for available execution environment.

        Returns:
            Dict mapping CLI name to execution env ("native", "wsl", or None).
        """
        results: dict[str, str | None] = {}

        # 1. Batch check native PATH first (instant)
        wsl_candidates: dict[str, str] = {}
        for name, command in commands.items():
            if which(command):
                results[name] = "native"
            else:
                wsl_candidates[name] = command

        # 2. WSL probe: single process checks all commands at once
        if wsl_candidates and self._has_wsl:
            wsl_results = await self._probe_wsl_batch(wsl_candidates)
            for name, command in wsl_candidates.items():
                if wsl_results.get(name):
                    # Double-check: if WSL found it, verify native really
                    # can't find it. PATH may have changed since the first
                    # check, or which() may behave differently in
                    # certain terminal contexts.
                    if which(command):
                        logger.info(f"  {name}: WSL 和 native 都有，优先 native")
                        results[name] = "native"
                    else:
                        results[name] = "wsl"
                else:
                    results[name] = None
        else:
            for name in wsl_candidates:
                results[name] = None

        return results

    async def _probe_wsl_batch(self, candidates: dict[str, str]) -> dict[str, bool]:
        """Batch-probe all commands in a single WSL process.

        Runs ``which`` or ``test -x`` for each command. If a command
        with an absolute path fails, it may be a permission issue
        (e.g. installed under /root/). The failure is logged with a
        hint so the user can fix it when they see the CLI as unavailable.
        """
        checks = []
        for name, command in candidates.items():
            if "/" in command:
                checks.append(f'test -x {command} && echo "{name}:ok" || echo "{name}:denied"')
            else:
                checks.append(f'which {command} >/dev/null 2>&1 && echo "{name}:ok"')
        script = "; ".join(checks)

        try:
            proc = await asyncio.create_subprocess_exec(
                "wsl", "bash", "-lc", script,
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=15)
            output = decode_process_output(stdout)
            results: dict[str, bool] = {}
            for name, command in candidates.items():
                if f"{name}:ok" in output:
                    results[name] = True
                else:
                    results[name] = False
                    # Log permission hint for absolute paths that failed
                    if "/" in command and f"{name}:denied" in output:
                        logger.warning(
                            f"WSL 探测失败（权限不足）: {name}, path={command}. "
                            f"建议: sudo cp {command} /usr/local/bin/ 或重新安装到用户可访问的路径"
                        )
            return results
        except Exception:
            return {name: False for name in candidates}

    async def _probe_command(self, command: str) -> str | None:
        """Probe which execution environment a command is available in.

        Args:
            command: CLI command to probe.

        Returns:
            "native", "wsl", or None if not found in any environment.
        """
        # 1. Try native PATH first
        if which(command):
            return "native"

        # 2. On Windows, also try WSL
        if not self._has_wsl:
            return None
        try:
            # Absolute paths use test -x, relative paths use which
            check = f"test -x {command}" if "/" in command else f"which {command}"
            proc = await asyncio.create_subprocess_exec(
                "wsl", "bash", "-lc", f"{check} 2>/dev/null && echo ok",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
            if "ok" in decode_process_output(stdout):
                return "wsl"
        except Exception as e:
            logger.debug(f"WSL 探测失败: command={name}, error={e}")

        return None

    def get_provider(self, name: str) -> Optional[AgentProvider]:
        return self._providers.get(name)

    def list_all(self) -> list[dict]:
        return [info.to_dict() for info in self._detected]

    def list_available(self) -> list[str]:
        return [info.name for info in self._detected if info.available]

    def get_execution_env(self, name: str) -> str | None:
        """Get the execution environment for a CLI.

        Checks runtime overrides first (set by WSL fallback or user config),
        then falls back to the detect_all probe result stored on the provider.

        Args:
            name: CLI adapter name (e.g. "kiro", "codex").

        Returns:
            "native", "wsl", or None if the CLI is not registered.
        """
        # Runtime override takes priority (e.g. WSL fallback → native)
        if name in self._env_overrides:
            return self._env_overrides[name]
        provider = self._providers.get(name)
        if provider:
            return provider.execution_env
        return None

    def set_execution_env(self, name: str, env: str) -> None:
        """Override the execution environment for a CLI at runtime.

        Called when WSL proxy activation fails and the system falls back
        to native execution. Also updates the provider's internal state
        so that initialize() and env_check() use the correct path.

        Args:
            name: CLI adapter name.
            env: New execution environment ("native" or "wsl").
        """
        old_env = self.get_execution_env(name)
        self._env_overrides[name] = env
        # Sync the provider object so initialize() reads the new value
        provider = self._providers.get(name)
        if provider:
            provider.execution_env = env
        logger.info(f"执行环境覆盖: {name}, {old_env} → {env}")

    # ── Plugin Agent injection/removal ──

    def inject_plugin_agent(self, name: str, config: dict) -> bool:
        """
        Inject a plugin Agent into the registry.

        config should contain: command, args, display_name, terminal_cmd,
        install_hint, install_packages (or install_npm for backward compat).
        Returns False if the name conflicts with a built-in or custom Agent.
        """
        # Check conflict with built-in Agent
        if name in ACP_REGISTRY:
            logger.warning(f"插件 Agent '{name}' 与内置 Agent 冲突，已跳过")
            return False

        # Check conflict with custom Agent
        custom = self._load_custom_agents()
        if name in custom:
            logger.warning(f"插件 Agent '{name}' 与自定义 Agent 冲突，已跳过")
            return False

        # Add to _detected, available=False (actual detection happens in detect_all)
        # install_packages takes priority; install_npm is backward compat
        # for old plugins that haven't migrated to the new format
        self._detected.append(ProviderInfo(
            name=name,
            display_name=config.get("display_name", name),
            available=False,
            install_hint=config.get("install_hint", ""),
            install_packages=config.get("install_packages"),
            install_npm=config.get("install_npm", ""),
            is_custom=False,
            source="plugin",
        ))
        logger.info(f"注入插件 Agent: {config.get('display_name', name)}")
        return True

    def eject_plugin_agent(self, name: str) -> bool:
        """Remove a plugin Agent from the registry.

        Args:
            name: CLI name to remove.

        Returns:
            True if the agent was found and removed, False otherwise.
        """
        found = False
        before = len(self._detected)
        self._detected = [i for i in self._detected if i.name != name]
        if len(self._detected) < before:
            found = True
        if self._providers.pop(name, None) is not None:
            found = True
        if found:
            logger.info(f"移除插件 Agent: {name}")
        return found

    # ── Custom Agent management ──

    def _custom_agents_path(self) -> str:
        """Path to the custom agents configuration file.

        Respects MOBILEFLOW_CONFIG_DIR env var (set by parent Agent
        when launching WSL child Agent, pointing to the Windows-side
        config directory via /mnt/c/... mapping).
        """
        import os
        config_dir = os.environ.get("MOBILEFLOW_CONFIG_DIR") or os.path.expanduser("~/.mobileflow")
        os.makedirs(config_dir, exist_ok=True)
        return os.path.join(config_dir, "custom_agents.json")

    def _load_custom_agents(self) -> dict[str, dict]:
        """Load custom agents from the configuration file.

        Returns:
            Dict mapping agent name to config dict.
        """
        from pathlib import Path
        from ..utils.json_file import load_json_file
        data = load_json_file(Path(self._custom_agents_path()), default={}, silent=True)
        return data if isinstance(data, dict) else {}

    def _save_custom_agents(self, agents: dict[str, dict]):
        """Save custom agents to the configuration file.

        Args:
            agents: Dict mapping agent name to config dict.
        """
        from pathlib import Path
        from ..utils.json_file import save_json_file
        save_json_file(Path(self._custom_agents_path()), agents)

    def add_custom_agent(self, name: str, command: str, args: list[str],
                         display_name: str) -> dict:
        """Add a custom Agent to the registry.

        Saves the agent config to custom_agents.json. Does NOT validate
        command accessibility — call validate_custom_command() separately
        before adding if you want upfront validation (the handler does this).

        Args:
            name: Unique identifier for the agent.
            command: CLI command path (absolute or in PATH).
            args: Command arguments.
            display_name: Human-readable name shown in the App.

        Returns:
            Dict with ``success`` bool and ``message`` string.
        """
        if name in ACP_REGISTRY:
            return R.fail(t("backend.nameConflict", name=name))
        custom = self._load_custom_agents()
        custom[name] = {
            "command": command,
            "args": args,
            "display_name": display_name,
        }
        self._save_custom_agents(custom)
        logger.info(f"添加自定义 Agent: {display_name} ({command})")
        return R.ok(t("backend.agentAdded", name=display_name))

    def _validate_custom_command(self, command: str) -> dict:
        """Validate that a custom agent command is accessible.

        For native commands: checks utils/command.which().
        For WSL absolute paths: checks test -x with default user.
        Returns actionable error messages for common issues.

        Args:
            command: CLI command path.

        Returns:
            Dict with ``accessible`` bool and ``message`` string.
        """
        import subprocess

        # Native PATH check
        if "/" not in command and "\\" not in command:
            if which(command):
                return {"accessible": True, "message": ""}
            # Try WSL
            if self._has_wsl:
                try:
                    result = subprocess.run(
                        ["wsl", "bash", "-lc", f"which {command} 2>/dev/null && echo ok"],
                        capture_output=True, text=True, timeout=10,
                    )
                    if "ok" in result.stdout:
                        return {"accessible": True, "message": ""}
                except Exception as e:
                    logger.debug(f"WSL 命令验证失败: command={command}, error={e}")
            return {"accessible": False, "message": t("backend.commandNotFound", command=command)}

        # Absolute path (likely WSL)
        if command.startswith("/"):
            if not self._has_wsl:
                return {"accessible": False, "message": t("backend.wslNotInstalled")}
            try:
                result = subprocess.run(
                    ["wsl", "bash", "-lc", f"test -x {command} && echo ok || echo denied"],
                    capture_output=True, text=True, timeout=10,
                )
                if "ok" in result.stdout:
                    return {"accessible": True, "message": ""}
                if "denied" in result.stdout:
                    return {
                        "accessible": False,
                        "message": t("backend.permissionDenied", command=command),
                    }
            except Exception as e:
                logger.debug(f"WSL 路径验证失败: command={command}, error={e}")
            return {"accessible": False, "message": t("backend.cannotVerifyPath", command=command)}

        # Windows absolute path
        from pathlib import Path as P
        if P(command).exists():
            return {"accessible": True, "message": ""}
        return {"accessible": False, "message": t("backend.fileNotFound", command=command)}

    def remove_custom_agent(self, name: str) -> dict:
        """Remove a custom Agent from the registry.

        Args:
            name: CLI name to remove.

        Returns:
            Dict with success bool and translated message string.
        """
        if name in ACP_REGISTRY:
            return R.fail(t("backend.cannotRemoveBuiltin"))
        custom = self._load_custom_agents()
        if name not in custom:
            return R.fail(t("backend.customNotFound", name=name))
        display = custom[name].get("display_name", name)
        del custom[name]
        self._save_custom_agents(custom)
        self._providers.pop(name, None)
        self._detected = [i for i in self._detected if i.name != name]
        logger.info(f"移除自定义 Agent: {display}")
        return R.ok(t("backend.agentRemoved", name=display))

    async def install_agent(self, name: str, progress_cb=None) -> dict:
        """Install an Agent CLI with all required npm packages.

        Iterates through install_packages in order, installing each via
        ``npm i -g``. Pushes progress updates via progress_cb after each step.
        On failure, rolls back already-installed packages to leave the system
        clean (install is atomic: all succeed or all are reverted).

        Backward compatible: if a config only has ``install_npm`` (old format),
        it's treated as a single-package install.

        Args:
            name: CLI identifier from ACP_REGISTRY.
            progress_cb: Optional async callback ``(cli, step, total, package, label, status)``
                for streaming install progress to the App.

        Returns:
            Dict with ``success`` (bool) and ``message`` (str).
        """
        config = ACP_REGISTRY.get(name)
        if not config:
            return R.fail(t("backend.unknownAgent", name=name))

        # Resolve package list (new format: install_packages, old format: install_npm)
        packages = config.get("install_packages", [])
        if not packages:
            old_npm = config.get("install_npm")
            if old_npm:
                packages = [{"package": old_npm, "label": config["display_name"]}]
        if not packages:
            return R.fail(t("backend.manualInstall"))

        npm_cmd = which("npm")
        if not npm_cmd:
            return R.fail(t("backend.npmNotFound"))

        display = config["display_name"]
        total = len(packages)
        installed_so_far: list[str] = []  # For rollback on failure

        logger.info(f"📦 安装 {display}: {total} 个包")

        for i, pkg_info in enumerate(packages):
            pkg_name = pkg_info["package"]
            pkg_label = pkg_info.get("label", pkg_name)
            step = i + 1

            # Push progress: installing step N of M
            if progress_cb:
                await progress_cb(name, step, total, pkg_name, pkg_label, "installing")

            logger.info(f"  📦 安装 ({step}/{total}): {pkg_name}")

            try:
                proc = await asyncio.create_subprocess_exec(
                    npm_cmd, "i", "-g", pkg_name,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=120)

                if proc.returncode != 0:
                    err = decode_process_output(stderr).strip()[-200:]
                    logger.error(f"  ❌ {pkg_name} 安装失败: {err}")
                    # Rollback already-installed packages
                    await self._rollback_packages(npm_cmd, installed_so_far, display)
                    return R.fail(t("backend.installFailed", name=pkg_label, error=err))

                installed_so_far.append(pkg_name)
                logger.info(f"  ✅ {pkg_name} 安装成功")

            except asyncio.TimeoutError:
                logger.error(f"  ❌ {pkg_name} 安装超时")
                await self._rollback_packages(npm_cmd, installed_so_far, display)
                return R.fail(t("backend.installTimeout", name=pkg_label))
            except Exception as e:
                logger.error(f"  ❌ {pkg_name} 安装出错: {e}")
                await self._rollback_packages(npm_cmd, installed_so_far, display)
                return R.fail(t("backend.installError", name=pkg_label, error=str(e)))

        # All packages installed — probe and register the provider
        found_env = await self._probe_command(config["command"])
        if found_env:
            provider = ACPProvider(
                command=config["command"],
                args=config["args"],
                execution_env=found_env,
                display_name=config["display_name"],
                event_bus=self._event_bus,
                install_hint=config.get("install_hint", ""),
                process_terminate_timeout=self._process_terminate_timeout,
            )
            self._providers[name] = provider
            for info in self._detected:
                if info.name == name:
                    info.available = True
                    break

        logger.info(f"✅ {display} 安装完成 ({total} 个包)")
        return R.ok(t("backend.installSuccess", name=display))

    async def _rollback_packages(self, npm_cmd: str, packages: list[str], display: str) -> None:
        """Rollback already-installed packages on install failure.

        Uninstalls packages in reverse order to leave the system clean.
        Errors during rollback are logged but not propagated — best-effort cleanup.

        Args:
            npm_cmd: Path to the npm binary.
            packages: List of npm package names to uninstall (in install order).
            display: CLI display name for logging.
        """
        if not packages:
            return
        logger.warning(f"🔄 回滚已安装的包: {packages}")
        for pkg in reversed(packages):
            try:
                proc = await asyncio.create_subprocess_exec(
                    npm_cmd, "uninstall", "-g", pkg,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                await asyncio.wait_for(proc.communicate(), timeout=30)
                logger.debug(f"  回滚: {pkg} 已卸载")
            except Exception as e:
                logger.warning(f"  回滚失败（可忽略）: {pkg}, error={e}")

    async def uninstall_agent(self, name: str, progress_cb=None) -> dict:
        """Uninstall an Agent CLI by removing all its npm packages.

        Iterates through install_packages in reverse order, uninstalling each
        via ``npm uninstall -g``. Pushes progress updates via progress_cb.

        Args:
            name: CLI identifier from ACP_REGISTRY.
            progress_cb: Optional async callback for streaming progress.

        Returns:
            Dict with ``success`` (bool) and ``message`` (str).
        """
        config = ACP_REGISTRY.get(name)
        if not config:
            return {"success": False, "message": t("backend.unknownAgent", name=name)}

        packages = config.get("install_packages", [])
        if not packages:
            old_npm = config.get("install_npm")
            if old_npm:
                packages = [{"package": old_npm, "label": config["display_name"]}]
        if not packages:
            return {"success": False, "message": t("backend.uninstallNotSupported")}

        npm_cmd = which("npm")
        if not npm_cmd:
            return {"success": False, "message": t("backend.npmNotFound")}

        display = config["display_name"]
        total = len(packages)
        # Uninstall in reverse order (ACP adapter first, then CLI body)
        reversed_packages = list(reversed(packages))

        logger.info(f"🗑️ 卸载 {display}: {total} 个包")

        for i, pkg_info in enumerate(reversed_packages):
            pkg_name = pkg_info["package"]
            pkg_label = pkg_info.get("label", pkg_name)
            step = i + 1

            if progress_cb:
                await progress_cb(name, step, total, pkg_name, pkg_label, "uninstalling")

            logger.info(f"  🗑️ 卸载 ({step}/{total}): {pkg_name}")

            try:
                proc = await asyncio.create_subprocess_exec(
                    npm_cmd, "uninstall", "-g", pkg_name,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=60)

                if proc.returncode != 0:
                    err = decode_process_output(stderr).strip()[-200:]
                    logger.warning(f"  ⚠️ {pkg_name} 卸载可能失败: {err}")
                else:
                    logger.info(f"  ✅ {pkg_name} 已卸载")

            except asyncio.TimeoutError:
                logger.warning(f"  ⚠️ {pkg_name} 卸载超时")
            except Exception as e:
                logger.warning(f"  ⚠️ {pkg_name} 卸载出错: {e}")

        # Remove provider and mark as unavailable
        self._providers.pop(name, None)
        for info in self._detected:
            if info.name == name:
                info.available = False
                break

        logger.info(f"✅ {display} 卸载完成")
        return {"success": True, "message": t("backend.uninstallSuccess", name=display)}
