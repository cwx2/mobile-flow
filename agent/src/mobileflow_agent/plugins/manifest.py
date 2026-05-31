"""Plugin manifest data models.

Defines the schema and validation rules for ``mobileflow.plugin.json``.
All Pydantic models use ``snake_case`` field names internally and map to
``camelCase`` via ``alias_generator`` for JSON manifest compatibility.

Called by:
    - plugins/loader.py (manifest parsing).
    - plugins/registry.py (reading plugin capability declarations).
    - server/handlers/plugin_handler.py (serialisation for the App).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, field_validator
from pydantic.alias_generators import to_camel


# Plugin ID validation pattern
_ID_PATTERN = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$")


# ── Pydantic sub-models ──

class ProviderDecl(BaseModel):
    """Declaration of a single Agent provider contributed by a plugin.

    Attributes:
        name: Unique provider name.
        command: CLI command to launch the agent.
        args: Additional command-line arguments.
        display_name: Human-readable name shown in the UI.
        terminal_cmd: Optional interactive TUI command (overrides ``command``).
        install_hint: User-facing installation instructions.
        install_npm: npm package name for one-click install.
    """

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
    )

    name: str
    command: str
    args: list[str] = []
    display_name: str = ""
    terminal_cmd: str | None = None
    install_hint: str = ""
    install_npm: str = ""


class UiHint(BaseModel):
    """UI presentation hints for a configuration field.

    Attributes:
        label: Display label.
        help: Optional help text.
        advanced: Whether to show this field in an "Advanced" section.
    """

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
    )

    label: str
    help: str = ""
    advanced: bool = False


class DangerousFlag(BaseModel):
    """Marker for a configuration value that is considered dangerous.

    Attributes:
        path: JSON path to the config field.
        equals: The value that triggers the dangerous flag.
    """

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
    )

    path: str
    equals: Any


class SecretInputs(BaseModel):
    """Declaration of secret input fields in the configuration.

    Attributes:
        paths: List of JSON path descriptors for secret fields.
    """

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
    )

    paths: list[dict] = []


class ConfigContracts(BaseModel):
    """Capability contracts: dangerous flags and secret inputs.

    Attributes:
        dangerous_flags: List of dangerous configuration markers.
        secret_inputs: Optional secret input declarations.
    """

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
    )

    dangerous_flags: list[DangerousFlag] = []
    secret_inputs: SecretInputs | None = None


# ── Main manifest model ──

class PluginManifest(BaseModel):
    """Data model for ``mobileflow.plugin.json``.

    Uses ``extra="allow"`` to preserve unknown fields for forward compatibility.

    Attributes:
        id: Unique plugin identifier (lowercase alphanumeric + hyphens).
        enabled_by_default: Whether the plugin is enabled on first discovery.
        providers: List of Agent provider declarations.
        provider_auth_env_vars: Mapping of provider name to required env vars.
        config_schema: Optional JSON Schema for plugin configuration.
        ui_hints: Mapping of config field path to UI hints.
        config_contracts: Optional capability contracts.
        platforms: Optional platform filter (``["windows", "macos", "linux"]``).
    """

    model_config = ConfigDict(
        extra="allow",
        alias_generator=to_camel,
        populate_by_name=True,
    )

    id: str
    enabled_by_default: bool = True
    providers: list[ProviderDecl] = []
    provider_auth_env_vars: dict[str, list[str]] = {}
    config_schema: dict | None = None
    ui_hints: dict[str, UiHint] = {}
    config_contracts: ConfigContracts | None = None
    platforms: list[str] | None = None

    @field_validator("id")
    @classmethod
    def validate_id(cls, v: str) -> str:
        """Validate that the plugin ID matches the required pattern."""
        if not _ID_PATTERN.match(v):
            raise ValueError(
                f"插件 ID '{v}' 格式不合法，"
                "只能包含小写字母、数字和连字符，"
                "且不能以连字符开头或结尾"
            )
        return v


# ── Dataclass helper models ──

@dataclass
class PluginMetadata:
    """Metadata extracted from ``package.json``.

    Attributes:
        name: Package name.
        version: Semantic version string.
        description: Short description.
        author: Author name or identifier.
        license: SPDX license identifier.
        repository: Repository URL.
    """

    name: str = ""
    version: str = ""
    description: str = ""
    author: str = ""
    license: str = ""
    repository: str = ""


@dataclass
class PluginInfo:
    """Complete plugin information (manifest + metadata + runtime state).

    Attributes:
        id: Unique plugin identifier.
        manifest: Parsed plugin manifest.
        metadata: Optional package.json metadata.
        directory: Filesystem path to the plugin directory.
        enabled: Whether the plugin is currently enabled.
        status: Runtime status (``active`` / ``error`` / ``disabled`` / ``unavailable``).
        error: Optional error message if the plugin failed to load.
    """

    id: str
    manifest: PluginManifest
    metadata: PluginMetadata | None
    directory: Path
    enabled: bool
    status: str
    error: str | None = None
