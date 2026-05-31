"""Persistent key storage for device pairing secrets.

Module: crypto/
Responsibility:
    1. Securely store pairing secrets (key seeds).
    2. Manage the paired device list (device_id → secret mapping).
    3. Device revocation (delete keys).

Called by:
    - CLI commands (pair, devices list, devices revoke).
    - daemon/manager.py (load keys on startup).
    - server/connection_manager.py (Relay mode authentication).

Storage strategy:
    - Prefer the system keyring (macOS Keychain, Linux Secret Service,
      Windows Credential Locker).
    - Fall back to encrypted file storage when the keyring is unavailable
      (e.g. headless Linux servers).
    - Device metadata (name, platform, pairing time) is stored in a plain
      JSON file (non-sensitive data).

Reference: Happy ``persistence.ts`` ``readPrivateKey`` / ``writePrivateKey``.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

from loguru import logger

from ..utils.json_file import load_json_file, save_json_file


@dataclass
class DeviceInfo:
    """Metadata for a paired device.

    Attributes:
        device_id: Unique device identifier.
        name: Human-readable device name (e.g. "iPhone 15").
        platform: Device platform (``ios`` / ``android``).
        paired_at: Pairing timestamp (Unix epoch seconds).
        last_seen: Last-online timestamp (Unix epoch seconds).
    """
    device_id: str
    name: str
    platform: str
    paired_at: float
    last_seen: float = 0.0


class KeyStore:
    """Persistent key storage backed by the system keyring or local files.

    Storage layout (``~/.mobileflow/``):
        - ``keys/``              — key file directory.
        - ``keys/{device_id}.key`` — hex-encoded 32-byte secret per device.
        - ``devices.json``       — device metadata list.

    Attributes:
        _KEYRING_SERVICE: Service name used for keyring entries.
    """

    _KEYRING_SERVICE = "mobileflow-agent"

    def __init__(self, data_dir: Optional[Path] = None):
        """Initialise the key store.

        Args:
            data_dir: Data directory path (defaults to ``~/.mobileflow``).
        """
        self._data_dir = data_dir or Path.home() / ".mobileflow"
        self._keys_dir = self._data_dir / "keys"
        self._devices_file = self._data_dir / "devices.json"

        self._keys_dir.mkdir(parents=True, exist_ok=True)

        # Detect keyring availability
        self._keyring_available = self._check_keyring()
        if self._keyring_available:
            logger.debug("KeyStore: 使用系统密钥存储（keyring）")
        else:
            logger.debug("KeyStore: keyring 不可用，使用文件存储")

    def _check_keyring(self) -> bool:
        """Check whether the system keyring is available.

        Returns:
            True if the keyring can be used, False otherwise.
        """
        try:
            import keyring
            # Attempt a read to verify the backend works
            keyring.get_password(self._KEYRING_SERVICE, "__test__")
            return True
        except Exception:
            return False

    # ── Secret storage ──

    def save_secret(self, device_id: str, secret: bytes) -> None:
        """Save a pairing secret for a device.

        Tries the system keyring first, falling back to file storage.

        Args:
            device_id: Unique device identifier.
            secret: 32-byte key seed.

        Raises:
            ValueError: If ``secret`` is not exactly 32 bytes.
        """
        if len(secret) != 32:
            raise ValueError(f"secret 必须是 32 字节，实际 {len(secret)} 字节")

        secret_hex = secret.hex()

        if self._keyring_available:
            try:
                import keyring
                keyring.set_password(
                    self._KEYRING_SERVICE,
                    f"device:{device_id}",
                    secret_hex,
                )
                logger.debug(f"KeyStore: secret 已保存到 keyring [{device_id}]")
                return
            except Exception as e:
                logger.warning(f"KeyStore: keyring 保存失败，回退到文件: {e}")

        # File storage fallback
        key_file = self._keys_dir / f"{device_id}.key"
        key_file.write_text(secret_hex, encoding="utf-8")
        # Restrict file permissions to owner-only (Unix)
        try:
            os.chmod(key_file, 0o600)
        except OSError:
            pass  # Windows does not support chmod
        logger.debug(f"KeyStore: secret 已保存到文件 [{device_id}]")

    def load_secret(self, device_id: str) -> Optional[bytes]:
        """Load a pairing secret for a device.

        Tries the system keyring first, falling back to file storage.

        Args:
            device_id: Unique device identifier.

        Returns:
            32-byte secret, or None if not found.
        """
        logger.debug(f"KeyStore: 加载 secret [{device_id}]")
        if self._keyring_available:
            try:
                import keyring
                secret_hex = keyring.get_password(
                    self._KEYRING_SERVICE,
                    f"device:{device_id}",
                )
                if secret_hex:
                    return bytes.fromhex(secret_hex)
            except Exception as e:
                logger.warning(f"KeyStore: keyring 读取失败: {e}")

        # File storage fallback
        key_file = self._keys_dir / f"{device_id}.key"
        if key_file.exists():
            try:
                secret_hex = key_file.read_text(encoding="utf-8").strip()
                if not secret_hex:
                    return None
                return bytes.fromhex(secret_hex)
            except (ValueError, OSError) as e:
                logger.error(f"KeyStore: 密钥文件损坏 [{device_id}]: {e}")

        return None

    def delete_secret(self, device_id: str) -> bool:
        """Delete a pairing secret for a device.

        Removes from both keyring and file storage.

        Args:
            device_id: Unique device identifier.

        Returns:
            True if a secret was found and deleted.
        """
        deleted = False

        if self._keyring_available:
            try:
                import keyring
                keyring.delete_password(
                    self._KEYRING_SERVICE,
                    f"device:{device_id}",
                )
                deleted = True
            except Exception:
                pass

        key_file = self._keys_dir / f"{device_id}.key"
        if key_file.exists():
            key_file.unlink()
            deleted = True

        if deleted:
            logger.info(f"KeyStore: secret 已删除 [{device_id}]")
        return deleted

    # ── Device metadata management ──

    def _load_devices(self) -> list[DeviceInfo]:
        """Load the device list from the JSON metadata file.

        Returns:
            List of DeviceInfo records (empty list on error).
        """
        data = load_json_file(self._devices_file, default=[])
        if not isinstance(data, list):
            return []
        try:
            return [DeviceInfo(**d) for d in data]
        except (TypeError, KeyError) as e:
            logger.error(f"KeyStore: devices.json 损坏: {e}")
            return []

    def _save_devices(self, devices: list[DeviceInfo]) -> None:
        """Persist the device list to the JSON metadata file.

        Args:
            devices: List of DeviceInfo records to save.
        """
        data = [asdict(d) for d in devices]
        save_json_file(self._devices_file, data)

    def add_device(self, device: DeviceInfo, secret: bytes) -> None:
        """Register a paired device (save secret + metadata).

        If a device with the same ID already exists, it is replaced.

        Args:
            device: Device metadata.
            secret: 32-byte key seed.
        """
        self.save_secret(device.device_id, secret)

        # Update device list (deduplicate by device_id)
        devices = self._load_devices()
        devices = [d for d in devices if d.device_id != device.device_id]
        devices.append(device)
        self._save_devices(devices)
        logger.info(
            f"KeyStore: 设备已添加 [{device.device_id}] {device.name} ({device.platform})"
        )

    def remove_device(self, device_id: str) -> bool:
        """Revoke a paired device (delete secret + metadata).

        Args:
            device_id: Unique device identifier.

        Returns:
            True if the device was found and removed.
        """
        self.delete_secret(device_id)

        devices = self._load_devices()
        before = len(devices)
        devices = [d for d in devices if d.device_id != device_id]
        self._save_devices(devices)

        removed = len(devices) < before
        if removed:
            logger.info(f"KeyStore: 设备已撤销 [{device_id}]")
        return removed

    def list_devices(self) -> list[DeviceInfo]:
        """Return all paired devices.

        Returns:
            List of DeviceInfo records.
        """
        return self._load_devices()

    def get_device(self, device_id: str) -> Optional[DeviceInfo]:
        """Look up a specific paired device.

        Args:
            device_id: Unique device identifier.

        Returns:
            DeviceInfo if found, None otherwise.
        """
        for d in self._load_devices():
            if d.device_id == device_id:
                return d
        return None

    def update_last_seen(self, device_id: str) -> None:
        """Update the last-seen timestamp for a device.

        Args:
            device_id: Unique device identifier.
        """
        devices = self._load_devices()
        for d in devices:
            if d.device_id == device_id:
                d.last_seen = time.time()
                self._save_devices(devices)
                return

    def has_devices(self) -> bool:
        """Check whether any devices are paired.

        Returns:
            True if at least one device is registered.
        """
        return len(self._load_devices()) > 0
