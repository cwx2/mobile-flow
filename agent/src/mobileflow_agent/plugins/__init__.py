"""
Plugin sub-package: core modules for the declarative plugin system.

Responsibility:
  Plugin discovery, validation, registration, and lifecycle management.
  Capabilities are declared via mobileflow.plugin.json manifest files,
  enabling discovery, validation, and registration without executing plugin code.

Called by:
  - server/handlers/plugin_handler.py (WebSocket message handling)
  - providers/registry.py (Agent-type plugin injection)
"""

# Data models
from .manifest import (
    PluginManifest,
    ProviderDecl,
    UiHint,
    ConfigContracts,
    DangerousFlag,
    SecretInputs,
    PluginMetadata,
    PluginInfo,
)

# Plugin loader
from .loader import PluginLoader

# Plugin registry
from .registry import PluginRegistry

__all__: list[str] = [
    "PluginManifest",
    "ProviderDecl",
    "UiHint",
    "ConfigContracts",
    "DangerousFlag",
    "SecretInputs",
    "PluginMetadata",
    "PluginInfo",
    "PluginLoader",
    "PluginRegistry",
]
