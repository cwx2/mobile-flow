"""Run Configuration service package.

Provides a structured, configuration-driven approach to running
project tasks. Replaces the ad-hoc Web Preview panel with persistent
configurations stored in `.mobileflow/run.json`.

Exports:
    - Data models: RunConfigType, RunConfigState, BeforeRunTask,
      PreviewSettings, TestSettings, RunConfiguration, RunConfigFile
    - Store: RunConfigurationStore (CRUD + persistence)
    - Executor: RunConfigurationExecutor (lifecycle engine)
"""

from __future__ import annotations

from .executor import RunConfigurationExecutor
from .models import (
    BeforeRunTask,
    PreviewSettings,
    RunConfigFile,
    RunConfigState,
    RunConfigType,
    RunConfiguration,
    TestSettings,
)
from .store import RunConfigurationStore

__all__ = [
    "BeforeRunTask",
    "PreviewSettings",
    "RunConfigFile",
    "RunConfigState",
    "RunConfigType",
    "RunConfiguration",
    "RunConfigurationExecutor",
    "RunConfigurationStore",
    "TestSettings",
]
