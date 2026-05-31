"""Run Configuration data models.

Defines the Pydantic models for the Run Configuration system:
configuration types, lifecycle states, before-run tasks, type-specific
settings, and the top-level persistence schema.

These models are serialized to `.mobileflow/run.json` for persistence
and transmitted over WebSocket for App/Dashboard communication.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field, field_validator


class RunConfigType(str, Enum):
    """Available configuration types.

    Each type determines default behavior and available settings:
    - preview: Web dev server with reverse proxy for phone access
    - script: One-off or long-running shell scripts
    - test: Test runner with optional pattern filtering
    - custom: Generic command with no type-specific behavior
    """

    PREVIEW = "preview"
    SCRIPT = "script"
    TEST = "test"
    CUSTOM = "custom"


class RunConfigState(str, Enum):
    """Process lifecycle states for a running configuration.

    State machine transitions:
        idle → before_run → starting → running → stopping → stopped
        Any state can transition to stopped on failure.
        stopped transitions back to idle on reset.
    """

    IDLE = "idle"
    BEFORE_RUN = "before_run"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    STOPPED = "stopped"


class BeforeRunTask(BaseModel):
    """A prerequisite command that runs before the main configuration.

    Before-run tasks execute sequentially in order. If any enabled task
    exits with a non-zero code, the entire execution is cancelled.

    Attributes:
        command: Shell command string to execute.
        working_directory: Optional working directory override. Defaults
            to the parent configuration's working_directory if not set.
        enabled: Whether this task should be executed. Disabled tasks
            are skipped without affecting the chain.
    """

    command: str
    working_directory: str | None = None
    enabled: bool = True


class PreviewSettings(BaseModel):
    """Additional settings for preview-type configurations.

    Controls how the reverse proxy connects to the target dev server
    and how the phone WebView interacts with the preview.

    Attributes:
        url: Target URL to proxy (e.g. "http://localhost:3000" or
            "https://de4.nmm.com:7001"). Must include scheme and host.
        host_header: Optional override for the Host header sent to the
            target. If not set, derived from the url's netloc portion.
        auto_refresh: Whether the phone WebView should reload when file
            changes are detected (with 500ms debounce).
    """

    url: str = "http://localhost:3000"
    host_header: str | None = None
    auto_refresh: bool = True

    @field_validator("url")
    @classmethod
    def validate_url(cls, v: str) -> str:
        """Verify that url contains a scheme and host.

        Args:
            v: The URL string to validate.

        Returns:
            The validated URL string.

        Raises:
            ValueError: If the URL is missing scheme or host.
        """
        from urllib.parse import urlparse

        parsed = urlparse(v)
        if not parsed.scheme:
            raise ValueError("Preview URL must include a scheme (http:// or https://)")
        if not parsed.hostname:
            raise ValueError("Preview URL must include a host")
        return v


class TestSettings(BaseModel):
    """Additional settings for test-type configurations.

    Attributes:
        test_pattern: Optional glob or regex for filtering test files.
            Passed to the test runner command if specified.
    """

    test_pattern: str | None = None


class RunConfiguration(BaseModel):
    """A single run configuration with all fields.

    Represents a named, persisted set of parameters that defines how
    to run a specific project task. Stored in `.mobileflow/run.json`
    and transmitted over WebSocket for remote execution from the phone.

    Attributes:
        id: Unique identifier (UUID string). Auto-generated on creation.
        name: User-visible display name shown in the configuration list.
        type: Configuration type determining behavior and available settings.
        command: Shell command string to execute. Required for execution.
        working_directory: Working directory for the subprocess. Relative
            paths are resolved against the project root. None means project root.
        environment_variables: Key-value map of environment variable overrides.
            Merged on top of the parent process environment.
        pass_parent_env: Whether to inherit the parent process environment.
            If false, only environment_variables are set.
        allow_parallel: Whether multiple instances of this configuration can
            run simultaneously. False enforces singleton policy (stop existing
            before starting new).
        before_run_tasks: Ordered list of prerequisite commands. Executed
            sequentially before the main command.
        is_temporary: Whether this is a Quick Run temporary configuration.
            Temporary configs are subject to LRU eviction (max 5).
        folder_name: Optional grouping label for organizing configurations
            in the list UI. None means ungrouped.
        created_at: ISO 8601 timestamp of when this configuration was created.
        last_used_at: ISO 8601 timestamp of the last execution. None if
            never executed.
        preview: Type-specific settings for preview configurations.
            Only meaningful when type is PREVIEW.
        test: Type-specific settings for test configurations.
            Only meaningful when type is TEST.
    """

    # Identity
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    type: RunConfigType

    # Execution
    command: str = ""
    working_directory: str | None = None
    environment_variables: dict[str, str] = Field(default_factory=dict)
    pass_parent_env: bool = True

    # Lifecycle
    allow_parallel: bool = False
    before_run_tasks: list[BeforeRunTask] = Field(default_factory=list)

    # Metadata
    is_temporary: bool = False
    folder_name: str | None = None
    created_at: str = Field(default_factory=lambda: datetime.now().isoformat())
    last_used_at: str | None = None

    # Type-specific settings
    preview: PreviewSettings | None = None
    test: TestSettings | None = None

    @field_validator("command")
    @classmethod
    def validate_command_not_whitespace_only(cls, v: str) -> str:
        """Allow empty command (not yet configured) but reject whitespace-only.

        The executor performs the actual "command required" check at runtime.
        This validator catches obviously invalid whitespace-only commands
        during model construction.

        Args:
            v: The command string.

        Returns:
            The command string (stripped if whitespace-only and non-empty).

        Raises:
            ValueError: If command is non-empty but contains only whitespace.
        """
        if v and not v.strip():
            raise ValueError("Command must not be whitespace-only")
        return v


class RunConfigFile(BaseModel):
    """Top-level schema for .mobileflow/run.json.

    Wraps the configuration list with a schema version for forward
    compatibility and tracks the currently selected configuration.

    Attributes:
        version: Schema version integer. Currently 1. Incremented on
            breaking schema changes for migration support.
        configurations: Ordered list of all run configurations.
            Order determines display order in the UI.
        selected_id: ID of the currently selected/highlighted configuration.
            None if no configuration is selected.
    """

    version: int = 1
    configurations: list[RunConfiguration] = Field(default_factory=list)
    selected_id: str | None = None
