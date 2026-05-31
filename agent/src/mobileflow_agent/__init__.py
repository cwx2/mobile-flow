"""MobileFlow Desktop Agent — phone-to-desktop AI coding bridge.

Exports:
    __version__: Package version from pyproject.toml (e.g. "0.1.0").
    __app_name__: Package name from metadata (e.g. "mobileflow-agent").
        Used as client_info.name in ACP initialize handshake.
"""

from importlib.metadata import version, metadata, PackageNotFoundError

try:
    __version__ = version("mobileflow-agent")
    __app_name__ = metadata("mobileflow-agent")["Name"]
except PackageNotFoundError:
    __version__ = "0.1.0"
    __app_name__ = "mobileflow-agent"
