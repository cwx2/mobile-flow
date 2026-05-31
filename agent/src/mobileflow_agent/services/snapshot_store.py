"""Three-layer file snapshot store for diff and undo operations.

Modelled after VS Code's ``ChatEditingSession`` + ``ChatEditingModifiedDocumentEntry``:
    - ``initialContent``: session-level — content before the AI first touched the file.
      Used for "Undo All AI changes".
    - ``promptBaseline``: turn-level — content at the start of each prompt turn.
      Used for "Undo this prompt's changes".
    - ``editBaseline``: edit-level — content before each individual AI edit.
      Used for diff display and single-edit Reject.

Design:
    - In-memory cache only (no disk persistence); cleared on Agent restart.
    - Each file maintains three snapshot layers plus a full version history.
    - Supports checkpoints (named time-points for rollback).
    - Memory protection: max 20 versions per file, 50 MB total.

Called by:
    - acp_client.py (saves editBaseline on ToolCallStart).
    - file_handler.py (reads snapshots for Accept / Reject / Undo All).
    - cli_manager.py (saves promptBaseline at prompt start).
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Optional

from loguru import logger


@dataclass
class FileVersion:
    """A single versioned snapshot of a file's content.

    Attributes:
        content: Full file content at this version.
        timestamp: Capture time in milliseconds since epoch.
        source: Description of what triggered this snapshot.
    """
    content: str
    timestamp: int
    source: str = ""


@dataclass
class FileEntry:
    """Three-layer snapshot entry for a single file.

    Snapshot layers (following the VS Code pattern):
        - ``initial_content``: content before the AI first touched the file
          (session-level, immutable).
        - ``prompt_baseline``: content at the start of the current prompt turn
          (updated each turn).
        - ``edit_baseline``: content before the most recent AI edit
          (updated each edit).

    Attributes:
        path: Relative file path.
        initial_content: Session-level snapshot (pre-AI).
        prompt_baseline: Turn-level snapshot (pre-prompt).
        edit_baseline: Edit-level snapshot (pre-edit).
        versions: Chronological list of all edit baselines for checkpoint rollback.
    """
    path: str
    initial_content: str = ""
    prompt_baseline: str = ""
    edit_baseline: str = ""
    versions: list[FileVersion] = field(default_factory=list)

    @property
    def version_count(self) -> int:
        """Return the number of stored versions."""
        return len(self.versions)


class SnapshotStore:
    """File snapshot manager implementing the three-layer architecture.

    Typical usage flow:
        1. Prompt starts → ``mark_prompt_start(path, content)`` updates promptBaseline.
        2. Before AI edit → ``capture_before_edit(path, content)`` updates editBaseline.
        3. Diff display → ``get_edit_baseline(path)`` as old, disk content as new.
        4. Accept → ``clear_edit_baseline(path)``.
        5. Reject → ``get_edit_baseline(path)`` to roll back the file.
        6. Undo All → ``get_initial_content(path)`` to restore pre-AI state.
        7. Undo Prompt → ``get_prompt_baseline(path)`` to restore pre-turn state.

    Attributes:
        MAX_VERSIONS_PER_FILE: Maximum version history entries per file.
        MAX_TOTAL_BYTES: Maximum total memory budget for all snapshots.
    """

    MAX_VERSIONS_PER_FILE = 20
    MAX_TOTAL_BYTES = 50 * 1024 * 1024  # 50 MB

    def __init__(self):
        self._files: dict[str, FileEntry] = {}
        self._checkpoints: list[Checkpoint] = []
        self._total_bytes = 0

    # ── Layer 1: initialContent (session-level) ──

    def get_initial_content(self, path: str) -> Optional[str]:
        """Get the content from before the AI first touched the file (Undo All).

        Args:
            path: Relative file path.

        Returns:
            The initial content string, or None if no snapshot exists.
        """
        entry = self._files.get(path)
        return entry.initial_content if entry else None

    # ── Layer 2: promptBaseline (turn-level) ──

    def mark_prompt_start(self, path: str, content: str):
        """Record the current file content as the prompt baseline.

        Called at the start of each prompt turn.  If this is the first time
        the file is seen, ``initialContent`` is also set.

        Args:
            path: Relative file path.
            content: Current file content.
        """
        entry = self._ensure_entry(path, content)
        entry.prompt_baseline = content
        logger.debug(f"Prompt baseline: {path} ({len(content)} chars)")

    def get_prompt_baseline(self, path: str) -> Optional[str]:
        """Get the content from the start of the current prompt turn (Undo Prompt).

        Args:
            path: Relative file path.

        Returns:
            The prompt baseline content, or None if no snapshot exists.
        """
        entry = self._files.get(path)
        return entry.prompt_baseline if entry else None

    # ── Layer 3: editBaseline (edit-level) ──

    def capture_before_edit(self, path: str, content: str) -> int:
        """Record the current content as the edit baseline before an AI edit.

        Also appends the content to the version history for checkpoint rollback.

        Args:
            path: Relative file path.
            content: Current file content.

        Returns:
            The version number of the newly stored snapshot.
        """
        entry = self._ensure_entry(path, content)
        entry.edit_baseline = content

        # Append to version history
        self._enforce_limits(path, len(content))
        version = FileVersion(
            content=content,
            timestamp=int(time.time() * 1000),
            source="before_edit",
        )
        entry.versions.append(version)
        self._total_bytes += len(content)
        ver_num = len(entry.versions) - 1
        logger.debug(f"Edit baseline: {path} v{ver_num} ({len(content)} chars, total {self._total_bytes // 1024}KB)")
        return ver_num

    def get_edit_baseline(self, path: str) -> Optional[str]:
        """Get the content from before the most recent AI edit (diff / Reject).

        Args:
            path: Relative file path.

        Returns:
            The edit baseline content, or None if no snapshot exists.
        """
        entry = self._files.get(path)
        return entry.edit_baseline if entry else None

    # ── Version history ──

    def get_version(self, path: str, version: int) -> Optional[str]:
        """Get the content of a specific version.

        Args:
            path: Relative file path.
            version: Zero-based version index.

        Returns:
            The file content at that version, or None if not found.
        """
        entry = self._files.get(path)
        if not entry or version >= len(entry.versions):
            return None
        return entry.versions[version].content

    def get_version_count(self, path: str) -> int:
        """Return the number of stored versions for a file.

        Args:
            path: Relative file path.

        Returns:
            Version count (0 if the file has no snapshots).
        """
        entry = self._files.get(path)
        return entry.version_count if entry else 0

    def get_file_history(self, path: str) -> Optional[FileEntry]:
        """Get the complete snapshot entry for a file.

        Args:
            path: Relative file path.

        Returns:
            The FileEntry, or None if no snapshots exist.
        """
        return self._files.get(path)

    def list_modified_files(self) -> list[str]:
        """List all files that have been modified by the AI.

        Returns:
            List of relative file paths.
        """
        return list(self._files.keys())

    # ── Checkpoint ──

    def create_checkpoint(self, description: str = "") -> int:
        """Create a checkpoint marking the current state of all tracked files.

        Args:
            description: Human-readable description of the checkpoint.

        Returns:
            The checkpoint ID (zero-based index).
        """
        cp = Checkpoint(
            id=len(self._checkpoints),
            timestamp=int(time.time() * 1000),
            description=description,
            file_versions={
                path: entry.version_count - 1
                for path, entry in self._files.items()
                if entry.versions
            },
        )
        self._checkpoints.append(cp)
        logger.debug(f"Checkpoint #{cp.id}: {description} ({len(cp.file_versions)} files)")
        return cp.id

    def get_checkpoint(self, checkpoint_id: int) -> Optional["Checkpoint"]:
        """Retrieve a checkpoint by ID.

        Args:
            checkpoint_id: Zero-based checkpoint index.

        Returns:
            The Checkpoint, or None if the ID is out of range.
        """
        if 0 <= checkpoint_id < len(self._checkpoints):
            return self._checkpoints[checkpoint_id]
        return None

    def restore_checkpoint(self, checkpoint_id: int) -> dict[str, str]:
        """Get the file contents at a given checkpoint (does not write to disk).

        Args:
            checkpoint_id: Zero-based checkpoint index.

        Returns:
            Dict mapping ``{path: content_to_restore}``.
        """
        cp = self.get_checkpoint(checkpoint_id)
        if not cp:
            return {}
        result = {}
        for path, ver_idx in cp.file_versions.items():
            content = self.get_version(path, ver_idx)
            if content is not None:
                result[path] = content
        return result

    # ── Cleanup ──

    def clear_file(self, path: str):
        """Remove all snapshots for a single file (called after Accept).

        Args:
            path: Relative file path.
        """
        entry = self._files.pop(path, None)
        if entry:
            self._total_bytes -= sum(len(v.content) for v in entry.versions)

    def clear(self):
        """Remove all snapshots (called on session end)."""
        logger.debug(f"清除所有快照: {len(self._files)} 个文件, {self._total_bytes // 1024}KB")
        self._files.clear()
        self._checkpoints.clear()
        self._total_bytes = 0

    @property
    def stats(self) -> dict:
        """Return summary statistics about the snapshot store.

        Returns:
            Dict with ``files``, ``versions``, ``checkpoints``, and
            ``memory_bytes`` keys.
        """
        total_versions = sum(e.version_count for e in self._files.values())
        return {
            "files": len(self._files),
            "versions": total_versions,
            "checkpoints": len(self._checkpoints),
            "memory_bytes": self._total_bytes,
        }

    # ── Internal helpers ──

    def _ensure_entry(self, path: str, content: str) -> FileEntry:
        """Ensure a FileEntry exists, creating one with initialContent on first access.

        Args:
            path: Relative file path.
            content: Current file content (used as initialContent if new).

        Returns:
            The existing or newly created FileEntry.
        """
        if path not in self._files:
            self._files[path] = FileEntry(
                path=path,
                initial_content=content,
                prompt_baseline=content,
                edit_baseline=content,
            )
            logger.debug(f"New file entry: {path} (initial={len(content)} chars)")
        return self._files[path]

    def _enforce_limits(self, path: str, new_size: int):
        """Enforce per-file version count and total memory limits.

        Evicts the second-oldest version (preserving v0 = initial) when limits
        are exceeded.

        Args:
            path: File being updated.
            new_size: Size in bytes of the new version about to be added.
        """
        entry = self._files.get(path)
        if entry:
            # Per-file version cap: keep v0 (initial) and newest, evict middle
            while len(entry.versions) >= self.MAX_VERSIONS_PER_FILE:
                if len(entry.versions) > 1:
                    removed = entry.versions.pop(1)
                    self._total_bytes -= len(removed.content)
                else:
                    break

        # Total memory cap
        while self._total_bytes + new_size > self.MAX_TOTAL_BYTES and self._files:
            largest = max(self._files.values(), key=lambda e: len(e.versions))
            if len(largest.versions) > 1:
                removed = largest.versions.pop(1)
                self._total_bytes -= len(removed.content)
            else:
                break


@dataclass
class Checkpoint:
    """A named time-point snapshot across all tracked files.

    Attributes:
        id: Zero-based checkpoint index.
        timestamp: Creation time in milliseconds since epoch.
        description: Human-readable label.
        file_versions: Mapping of file path to version index at this checkpoint.
    """
    id: int
    timestamp: int
    description: str
    file_versions: dict[str, int] = field(default_factory=dict)
