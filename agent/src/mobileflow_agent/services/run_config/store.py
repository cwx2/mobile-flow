"""Run Configuration persistence store.

Manages CRUD operations and persistence for run configurations.
Configurations are stored in `.mobileflow/run.json` within the
project's working directory.

Responsibilities:
    - Load and validate configurations from disk on init.
    - Persist changes to disk on every mutation (create/update/delete/reorder).
    - Provide CRUD operations with template defaults per type.
    - Enforce temporary configuration LRU eviction (max 5).
    - Track the currently selected configuration.
"""

from __future__ import annotations

import uuid
from pathlib import Path
from typing import Literal

from loguru import logger

from ...utils.json_file import load_json_file, save_json_file
from .models import (
    PreviewSettings,
    RunConfigFile,
    RunConfiguration,
    RunConfigType,
)

# Maximum number of temporary configurations before LRU eviction
_MAX_TEMPORARY_CONFIGS = 5


class RunConfigurationStore:
    """Configuration persistence and CRUD operations.

    Loads configurations from disk on init, validates entries,
    and writes back on every mutation. The store is the single
    source of truth for configuration data.

    Attributes:
        _work_dir: Project root directory path.
        _file_path: Path to `.mobileflow/run.json`.
        _configurations: In-memory ordered list of configurations.
        _selected_id: ID of the currently selected configuration.
    """

    def __init__(self, work_dir: str) -> None:
        """Initialize the store with the project root directory.

        Args:
            work_dir: Absolute path to the project root directory.
                The configuration file will be at `{work_dir}/.mobileflow/run.json`.
        """
        self._work_dir = Path(work_dir)
        self._file_path = self._work_dir / ".mobileflow" / "run.json"
        self._configurations: list[RunConfiguration] = []
        self._selected_id: str | None = None
        logger.debug(f"RunConfigurationStore 初始化: work_dir={work_dir}")

    @property
    def selected_id(self) -> str | None:
        """ID of the currently selected configuration."""
        return self._selected_id

    @property
    def configurations(self) -> list[RunConfiguration]:
        """All configurations in display order."""
        return self._configurations

    def load(self) -> None:
        """Read `.mobileflow/run.json` from disk and populate internal state.

        Validates each entry individually. Invalid entries are skipped
        with a warning log, allowing the remaining valid configurations
        to load successfully.
        """
        raw_data = load_json_file(self._file_path, default=None)
        if raw_data is None:
            logger.debug("配置文件不存在，使用空配置列表")
            self._configurations = []
            self._selected_id = None
            return

        # Validate top-level structure
        if not isinstance(raw_data, dict):
            logger.warning(f"配置文件格式错误（非对象），跳过: {self._file_path}")
            self._configurations = []
            self._selected_id = None
            return

        self._selected_id = raw_data.get("selected_id")
        raw_configs = raw_data.get("configurations", [])

        if not isinstance(raw_configs, list):
            logger.warning("配置文件 configurations 字段不是数组，使用空列表")
            self._configurations = []
            return

        valid_configs: list[RunConfiguration] = []
        for i, entry in enumerate(raw_configs):
            try:
                config = RunConfiguration.model_validate(entry)
                valid_configs.append(config)
            except Exception as e:
                logger.warning(f"跳过无效配置条目 #{i}: {e}")

        self._configurations = valid_configs
        logger.info(
            f"加载运行配置: {len(valid_configs)}/{len(raw_configs)} 条有效, "
            f"selected_id={self._selected_id}"
        )

    def save(self) -> None:
        """Write the current state to `.mobileflow/run.json`.

        Creates the `.mobileflow/` directory if it does not exist.
        Output is pretty-printed JSON with 2-space indentation for
        human readability and meaningful VCS diffs.
        """
        config_file = RunConfigFile(
            version=1,
            configurations=self._configurations,
            selected_id=self._selected_id,
        )
        data = config_file.model_dump(mode="json")
        success = save_json_file(self._file_path, data, indent=2)
        if success:
            logger.debug(f"保存运行配置: {len(self._configurations)} 条")
        else:
            logger.error(f"保存运行配置失败: {self._file_path}")

    def list_all(self) -> list[RunConfiguration]:
        """Return all configurations in display order.

        Returns:
            Ordered list of all run configurations.
        """
        return self._configurations

    def get(self, config_id: str) -> RunConfiguration | None:
        """Return a single configuration by ID.

        Args:
            config_id: The UUID string of the configuration to find.

        Returns:
            The matching RunConfiguration, or None if not found.
        """
        for config in self._configurations:
            if config.id == config_id:
                return config
        return None

    def create(
        self,
        config_type: RunConfigType,
        initial: dict | None = None,
    ) -> RunConfiguration:
        """Create a new configuration with template defaults.

        Generates a unique UUID, applies type-specific template defaults,
        then overlays any provided initial field values. Enforces the
        temporary configuration LRU eviction limit.

        Args:
            config_type: The type of configuration to create.
            initial: Optional dict of field overrides to apply on top
                of the template defaults.

        Returns:
            The newly created RunConfiguration.
        """
        # Build template defaults based on type
        defaults = self._get_template_defaults(config_type)

        # Apply initial overrides
        if initial:
            defaults.update(initial)

        # Ensure required fields
        defaults["id"] = str(uuid.uuid4())
        defaults["type"] = config_type

        config = RunConfiguration.model_validate(defaults)

        # LRU eviction for temporary configs
        if config.is_temporary:
            self._evict_temporary_if_needed()

        self._configurations.append(config)
        self.save()
        logger.info(f"创建运行配置: name={config.name!r}, type={config_type.value}, id={config.id[:16]}...")
        return config

    def update(self, config_id: str, updates: dict) -> RunConfiguration | None:
        """Partial field update for an existing configuration.

        Only the fields present in `updates` are changed; all other
        fields are preserved unchanged.

        Args:
            config_id: ID of the configuration to update.
            updates: Dict of field_name → new_value. Only mutable fields
                should be included.

        Returns:
            The updated RunConfiguration, or None if not found.
        """
        for i, config in enumerate(self._configurations):
            if config.id == config_id:
                # Dump current state, apply updates, re-validate
                current_data = config.model_dump(mode="json")
                current_data.update(updates)
                # Preserve the original ID (prevent accidental override)
                current_data["id"] = config_id
                updated_config = RunConfiguration.model_validate(current_data)
                self._configurations[i] = updated_config
                self.save()
                logger.debug(
                    f"更新运行配置: id={config_id[:16]}..., "
                    f"fields={list(updates.keys())}"
                )
                return updated_config
        logger.warning(f"更新运行配置失败，未找到: id={config_id}")
        return None

    def delete(self, config_id: str) -> bool:
        """Remove a configuration by ID.

        If the deleted configuration was the currently selected one,
        the selection is cleared (selected_id set to None).

        Args:
            config_id: ID of the configuration to delete.

        Returns:
            True if the configuration was found and deleted, False otherwise.
        """
        original_len = len(self._configurations)
        self._configurations = [c for c in self._configurations if c.id != config_id]

        if len(self._configurations) == original_len:
            logger.warning(f"删除运行配置失败，未找到: id={config_id}")
            return False

        # Clear selection if the deleted config was selected
        if self._selected_id == config_id:
            self._selected_id = None
            logger.debug("已清除选中配置（被删除的配置是当前选中项）")

        self.save()
        logger.info(f"删除运行配置: id={config_id[:16]}...")
        return True

    def duplicate(self, config_id: str) -> RunConfiguration | None:
        """Deep copy a configuration with a new ID and "(Copy)" suffix.

        The duplicate is inserted immediately after the original in
        the configuration list.

        Args:
            config_id: ID of the configuration to duplicate.

        Returns:
            The new duplicated RunConfiguration, or None if source not found.
        """
        source = self.get(config_id)
        if source is None:
            logger.warning(f"复制运行配置失败，未找到: id={config_id}")
            return None

        # Deep copy via model serialization
        data = source.model_dump(mode="json")
        data["id"] = str(uuid.uuid4())
        data["name"] = f"{source.name} (Copy)"

        new_config = RunConfiguration.model_validate(data)

        # Insert after the original
        source_index = next(
            i for i, c in enumerate(self._configurations) if c.id == config_id
        )
        self._configurations.insert(source_index + 1, new_config)
        self.save()
        logger.info(
            f"复制运行配置: source={config_id[:16]}..., "
            f"new={new_config.id[:16]}..., name={new_config.name!r}"
        )
        return new_config

    def reorder(self, config_id: str, direction: Literal["up", "down"]) -> bool:
        """Move a configuration up or down in the list.

        Args:
            config_id: ID of the configuration to move.
            direction: "up" to move toward index 0, "down" to move toward end.

        Returns:
            True if the move was performed, False if the config was not found
            or is already at the boundary.
        """
        index = self._find_index(config_id)
        if index is None:
            logger.warning(f"重排运行配置失败，未找到: id={config_id}")
            return False

        if direction == "up":
            if index == 0:
                return False
            target = index - 1
        else:
            if index == len(self._configurations) - 1:
                return False
            target = index + 1

        # Swap positions
        self._configurations[index], self._configurations[target] = (
            self._configurations[target],
            self._configurations[index],
        )
        self.save()
        logger.debug(f"重排运行配置: id={config_id[:16]}..., {direction} ({index} → {target})")
        return True

    def select(self, config_id: str | None) -> None:
        """Set the currently selected configuration.

        Args:
            config_id: ID of the configuration to select, or None to clear.
        """
        self._selected_id = config_id
        self.save()
        logger.debug(f"选中运行配置: id={config_id[:16] + '...' if config_id else 'None'}")

    # ──────────────────────────────────────────────────────────────────
    # Private helpers
    # ──────────────────────────────────────────────────────────────────

    def _find_index(self, config_id: str) -> int | None:
        """Find the list index of a configuration by ID.

        Args:
            config_id: The configuration ID to search for.

        Returns:
            The index in self._configurations, or None if not found.
        """
        for i, config in enumerate(self._configurations):
            if config.id == config_id:
                return i
        return None

    def _get_template_defaults(self, config_type: RunConfigType) -> dict:
        """Return template default values for a given configuration type.

        Each type has sensible defaults so users spend less time on
        boilerplate setup when creating new configurations.

        Args:
            config_type: The type to get defaults for.

        Returns:
            Dict of field defaults suitable for RunConfiguration construction.
        """
        from datetime import datetime

        base = {
            "created_at": datetime.now().isoformat(),
            "is_temporary": False,
        }

        if config_type == RunConfigType.PREVIEW:
            return {
                **base,
                "name": "New Preview",
                "command": "",
                "allow_parallel": False,
                "preview": PreviewSettings(
                    url="http://localhost:3000",
                    auto_refresh=True,
                ).model_dump(mode="json"),
            }
        elif config_type == RunConfigType.SCRIPT:
            return {
                **base,
                "name": "New Script",
                "command": "",
                "allow_parallel": True,
            }
        elif config_type == RunConfigType.TEST:
            return {
                **base,
                "name": "New Test",
                "command": "",
                "allow_parallel": False,
            }
        else:  # CUSTOM
            return {
                **base,
                "name": "New Custom",
                "command": "",
                "allow_parallel": False,
            }

    def _evict_temporary_if_needed(self) -> None:
        """Evict the least-recently-used temporary config if at capacity.

        When the count of temporary configurations reaches the limit,
        removes the one with the oldest `last_used_at` timestamp
        (falls back to `created_at` if never used).
        """
        temp_configs = [c for c in self._configurations if c.is_temporary]
        if len(temp_configs) < _MAX_TEMPORARY_CONFIGS:
            return

        # Sort by last_used_at (or created_at as fallback), oldest first
        def sort_key(c: RunConfiguration) -> str:
            return c.last_used_at or c.created_at

        temp_configs.sort(key=sort_key)
        evict = temp_configs[0]

        self._configurations = [c for c in self._configurations if c.id != evict.id]

        # Clear selection if evicted config was selected
        if self._selected_id == evict.id:
            self._selected_id = None

        logger.info(
            f"LRU 淘汰临时配置: name={evict.name!r}, id={evict.id[:16]}..., "
            f"last_used={evict.last_used_at or 'never'}"
        )
