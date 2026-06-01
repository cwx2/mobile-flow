"""User-specific configuration manager for Dashboard-editable settings.

Module: services/
Responsibility:
    Manage reading/writing ~/.mobileflow/user-config.json, providing a clean
    interface for the Dashboard API to get/set connection configuration
    without touching committed config files.

Config loading priority (low → high):
    config/default.json < ~/.mobileflow/user-config.json < MOBILEFLOW_* env vars

Called by:
    - server/dashboard_api.py (GET/save connection config endpoints)
    - core/config.py (_load_layered_config includes user-config layer)
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from loguru import logger
from pydantic import BaseModel, Field

from ..utils.json_file import load_json_file, save_json_file


class ConnectionConfigData(BaseModel):
    """Connection configuration fields editable via Dashboard.

    These fields map directly to AgentConfig fields and are persisted
    in ~/.mobileflow/user-config.json. Empty strings mean "not configured"
    (the mode won't start).

    Attributes:
        tunnel_tls_cert: Absolute path to TLS certificate file.
        tunnel_tls_key: Absolute path to TLS private key file.
        tunnel_bearer_token: Bearer token for Tunnel mode authentication.
        tunnel_port: Port for Tunnel WSS server.
        relay_url: WebSocket URL of the Relay Server.
    """

    tunnel_tls_cert: str = ""
    tunnel_tls_key: str = ""
    tunnel_bearer_token: str = ""
    tunnel_port: int = Field(default=9601, ge=1, le=65535)
    relay_url: str = ""


class ConnectionConfigValidator:
    """Validates connection configuration before persistence.

    Checks file existence for cert/key paths, URL scheme for relay,
    and port range. Returns a dict of field→error_message; empty dict
    means all fields are valid.
    """

    @staticmethod
    def validate(config: ConnectionConfigData) -> dict[str, str]:
        """Validate config fields.

        Args:
            config: The configuration to validate.

        Returns:
            Dict mapping field names to error messages. Empty if valid.
        """
        errors: dict[str, str] = {}

        # Validate TLS cert path (only if non-empty)
        if config.tunnel_tls_cert:
            if not Path(config.tunnel_tls_cert).is_file():
                errors["tunnel_tls_cert"] = f"文件不存在: {config.tunnel_tls_cert}"

        # Validate TLS key path (only if non-empty)
        if config.tunnel_tls_key:
            if not Path(config.tunnel_tls_key).is_file():
                errors["tunnel_tls_key"] = f"文件不存在: {config.tunnel_tls_key}"

        # If cert and key are both set, token should also be set
        if config.tunnel_tls_cert and config.tunnel_tls_key:
            if not config.tunnel_bearer_token:
                errors["tunnel_bearer_token"] = "配置了证书时必须设置 Bearer Token"

        # Validate port range
        if config.tunnel_port < 1 or config.tunnel_port > 65535:
            errors["tunnel_port"] = f"端口范围无效: {config.tunnel_port}（需要 1-65535）"

        # Validate relay URL scheme (only if non-empty)
        if config.relay_url:
            if not config.relay_url.startswith(("ws://", "wss://")):
                errors["relay_url"] = "URL 格式无效: 必须以 ws:// 或 wss:// 开头"

        return errors


class UserConfigManager:
    """Manages user-specific configuration persistence.

    Reads and writes ~/.mobileflow/user-config.json, providing a clean
    interface for the dashboard API to get/set connection configuration
    without touching committed config files.

    The file stores only user-overridden values. Missing keys fall back
    to config/default.json values via the layered config system.

    Attributes:
        _path: Path to the user config JSON file.
    """

    def __init__(self, config_path: Path | None = None):
        self._path = config_path or (Path.home() / ".mobileflow" / "user-config.json")

    @property
    def path(self) -> Path:
        """Return the user config file path."""
        return self._path

    def load(self) -> dict[str, Any]:
        """Load user config from disk.

        Returns empty dict on missing or malformed file (triggers fallback
        to defaults). Logs a warning on parse errors.

        Returns:
            Dict of user-overridden config values, or empty dict.
        """
        data = load_json_file(self._path, default={})
        if isinstance(data, dict):
            return data
        logger.warning(f"用户配置格式异常，使用空配置: {self._path}")
        return {}

    def save(self, data: dict[str, Any]) -> bool:
        """Persist user config to disk.

        Creates parent directories if needed.

        Args:
            data: Config dict to persist.

        Returns:
            True if saved successfully, False on error.
        """
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            return save_json_file(self._path, data)
        except Exception as e:
            logger.error(f"保存用户配置失败: {e}")
            return False

    def get_connection_config(self) -> ConnectionConfigData:
        """Extract connection-related fields from user config.

        Returns:
            ConnectionConfigData with values from user config (or defaults).
        """
        data = self.load()
        return ConnectionConfigData(
            tunnel_tls_cert=data.get("tunnel_tls_cert", ""),
            tunnel_tls_key=data.get("tunnel_tls_key", ""),
            tunnel_bearer_token=data.get("tunnel_bearer_token", ""),
            tunnel_port=data.get("tunnel_port", 9601),
            relay_url=data.get("relay_url", ""),
        )

    def set_connection_config(self, config: ConnectionConfigData) -> bool:
        """Update connection fields in user config (preserves other fields).

        Args:
            config: New connection configuration values.

        Returns:
            True if saved successfully.
        """
        data = self.load()
        data.update(config.model_dump())
        logger.info(f"保存连接配置: tunnel_port={config.tunnel_port}, "
                    f"relay_url={config.relay_url or '(空)'}, "
                    f"cert={'已配置' if config.tunnel_tls_cert else '未配置'}")
        return self.save(data)


def mask_token(token: str) -> str:
    """Mask a bearer token for display, showing only the last 4 characters.

    Args:
        token: The full token string.

    Returns:
        Masked string with asterisks, or empty string if token is empty.
        Tokens shorter than 5 chars are returned as-is (too short to mask).
    """
    if not token:
        return ""
    if len(token) <= 4:
        return token
    return "*" * (len(token) - 4) + token[-4:]
