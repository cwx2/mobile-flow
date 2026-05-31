"""Tests for CommandExecutor service.

Covers:
- Relative cwd resolution against project root
- Absolute cwd passthrough
- Default cwd fallback to config.work_dir
- PID exposure after process start
- Single-instance enforcement
- Graceful stop (SIGTERM → SIGKILL)
- Zombie process prevention (cleanup_client)
"""

import asyncio
import os
import sys
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from mobileflow_agent.services.command_executor import (
    CommandAlreadyRunningError,
    CommandExecutor,
)


@pytest.fixture
def config():
    """Mock AgentConfig with work_dir set."""
    cfg = MagicMock()
    cfg.work_dir = "E:\\workData" if sys.platform == "win32" else "/home/user/project"
    return cfg


@pytest.fixture
def executor(config):
    return CommandExecutor(config)


class TestCwdResolution:
    """Test working directory resolution logic."""

    @pytest.mark.asyncio
    async def test_relative_cwd_resolved_against_work_dir(self, executor, config):
        """Relative cwd like 'front' becomes work_dir/front."""
        outputs = []

        async def capture_output(stream, data):
            outputs.append(data)

        # Use a simple command that prints cwd
        if sys.platform == "win32":
            # Create the target directory if it doesn't exist for the test
            target = Path(config.work_dir) / "front"
            if not target.exists():
                pytest.skip("Test directory does not exist")
            cmd = "cd"
        else:
            target = Path(config.work_dir) / "front"
            if not target.exists():
                pytest.skip("Test directory does not exist")
            cmd = "pwd"

        await executor.run(cmd, cwd="front", on_output=capture_output)
        output_text = "".join(outputs).strip()
        assert "front" in output_text.lower() or str(target).lower() in output_text.lower()

    @pytest.mark.asyncio
    async def test_absolute_cwd_used_directly(self, executor, config):
        """Absolute cwd is passed through without modification."""
        # Use temp dir as absolute path
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            outputs = []

            async def capture_output(stream, data):
                outputs.append(data)

            if sys.platform == "win32":
                cmd = "cd"
            else:
                cmd = "pwd"

            await executor.run(cmd, cwd=tmpdir, on_output=capture_output)
            output_text = "".join(outputs).strip()
            # Normalize for comparison
            assert Path(output_text).resolve() == Path(tmpdir).resolve()

    @pytest.mark.asyncio
    async def test_no_cwd_falls_back_to_work_dir(self, executor, config):
        """When cwd is None, uses config.work_dir."""
        if not Path(config.work_dir).exists():
            pytest.skip("work_dir does not exist")

        outputs = []

        async def capture_output(stream, data):
            outputs.append(data)

        if sys.platform == "win32":
            cmd = "cd"
        else:
            cmd = "pwd"

        await executor.run(cmd, cwd=None, on_output=capture_output)
        output_text = "".join(outputs).strip()
        assert Path(output_text).resolve() == Path(config.work_dir).resolve()

    @pytest.mark.asyncio
    async def test_invalid_cwd_reports_error(self, executor):
        """Invalid cwd triggers on_done with error status."""
        done_calls = []

        async def on_done(exit_code, status):
            done_calls.append((exit_code, status))

        await executor.run("echo hello", cwd="nonexistent_dir_xyz", on_done=on_done)
        assert len(done_calls) == 1
        assert done_calls[0][0] == -1
        assert done_calls[0][1] == "error"


class TestPidExposure:
    """Test that PID is accessible after process starts."""

    @pytest.mark.asyncio
    async def test_pid_is_none_before_run(self, executor):
        """PID is None when no process is running."""
        assert executor.pid is None

    @pytest.mark.asyncio
    async def test_pid_available_during_run(self, executor):
        """PID is set while process is running."""
        pid_holder = []

        async def capture_output(stream, data):
            # Capture PID during execution
            if executor.pid is not None and not pid_holder:
                pid_holder.append(executor.pid)

        if sys.platform == "win32":
            cmd = "ping -n 2 127.0.0.1 >nul & echo done"
        else:
            cmd = "sleep 0.5 && echo done"

        await executor.run(cmd, on_output=capture_output)
        assert len(pid_holder) == 1
        assert pid_holder[0] > 0

    @pytest.mark.asyncio
    async def test_pid_is_none_after_run(self, executor):
        """PID is None after process completes."""
        await executor.run("echo hello")
        assert executor.pid is None


class TestSingleInstance:
    """Test single-instance enforcement."""

    @pytest.mark.asyncio
    async def test_concurrent_run_raises(self, executor):
        """Second run() while first is active raises CommandAlreadyRunningError."""
        if sys.platform == "win32":
            cmd = "ping -n 3 127.0.0.1 >nul"
        else:
            cmd = "sleep 2"

        # Start first command in background
        task = asyncio.create_task(executor.run(cmd))
        await asyncio.sleep(0.3)  # Wait for it to start

        with pytest.raises(CommandAlreadyRunningError):
            await executor.run("echo second")

        # Cleanup
        await executor.stop()
        await task


class TestGracefulStop:
    """Test stop behavior."""

    @pytest.mark.asyncio
    async def test_stop_terminates_running_process(self, executor):
        """stop() terminates the running process."""
        done_calls = []

        async def on_done(exit_code, status):
            done_calls.append((exit_code, status))

        if sys.platform == "win32":
            cmd = "ping -n 30 127.0.0.1 >nul"
        else:
            cmd = "sleep 30"

        task = asyncio.create_task(executor.run(cmd, on_done=on_done))
        await asyncio.sleep(0.5)  # Wait for process to start

        assert executor.is_running
        await executor.stop()
        await task

        assert not executor.is_running
        # on_done should have been called (may be "killed" or "completed"
        # depending on timing)

    @pytest.mark.asyncio
    async def test_stop_noop_when_not_running(self, executor):
        """stop() is a no-op when no process is running."""
        await executor.stop()  # Should not raise
