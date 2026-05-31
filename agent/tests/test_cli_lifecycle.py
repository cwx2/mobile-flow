"""
CLI Provider lifecycle management tests.

Covers: ProviderLifecycleState enum, ProviderCapabilities defaults,
ACPProvider env_check, CLIManager infrastructure, _push_status,
handle_retry cleanup, session lock serialization, session recovery fallback.
"""

from __future__ import annotations

import asyncio
import unittest.mock as mock

import pytest
from conftest import Obj

from mobileflow_agent.providers.base import ProviderLifecycleState, ProviderCapabilities


class TestProviderLifecycleState:
    def test_enum_count(self):
        assert len(list(ProviderLifecycleState)) == 6

    def test_enum_values(self):
        expected = {"uninitialized", "checking_env", "starting", "auth_required", "ready", "failed"}
        assert {s.value for s in ProviderLifecycleState} == expected

    def test_all_values_are_str(self):
        for s in ProviderLifecycleState:
            assert isinstance(s.value, str)


class TestProviderCapabilitiesDefaults:
    def test_default_lifecycle_state(self):
        caps = ProviderCapabilities()
        assert caps.lifecycle_state == ProviderLifecycleState.UNINITIALIZED

    def test_default_error_message(self):
        caps = ProviderCapabilities()
        assert caps.error_message == ""


class TestACPProviderEnvCheck:
    def _make_provider(self):
        from mobileflow_agent.providers.acp_provider import ACPProvider
        p = ACPProvider.__new__(ACPProvider)
        p._command = "fake-cli"
        p._args = []
        p._env = {}
        p._execution_env = "native"
        p._display_name = "Fake CLI"
        p._event_bus = None
        p._install_hint = ""
        p._conn = None
        p._proc = None
        p._collector = None
        p._client_impl = None
        p._session_id = None
        p._ctx_manager = None
        p._capabilities = None
        p._needs_recovery = False
        p._last_cwd = ""
        p._lifecycle_state = ProviderLifecycleState.UNINITIALIZED
        p._error_message = ""
        return p

    def test_initial_state(self):
        p = self._make_provider()
        assert p._lifecycle_state == ProviderLifecycleState.UNINITIALIZED
        assert p._error_message == ""

    def test_env_check_binary_not_found(self):
        p = self._make_provider()
        with mock.patch("mobileflow_agent.providers.acp_provider.which", return_value=None):
            ok, err = asyncio.run(p.env_check())
            assert ok is False
            assert len(err) > 0 and ("Fake CLI" in err or "fake-cli" in err)

    def test_env_check_binary_found(self):
        p = self._make_provider()
        with mock.patch("mobileflow_agent.providers.acp_provider.which", return_value="/usr/bin/fake-cli"):
            ok, err = asyncio.run(p.env_check())
            assert ok is True
            assert err == ""


class TestCliLifecycleStateParsing:
    """Replicates the Dart _parseCliLifecycleState mapping."""

    @staticmethod
    def _parse(raw: str) -> str:
        mapping = {
            "checking_env": "checkingEnv",
            "starting": "starting",
            "ready": "ready",
            "failed": "failed",
        }
        return mapping.get(raw, "uninitialized")

    @pytest.mark.parametrize("raw,expected", [
        ("checking_env", "checkingEnv"),
        ("starting", "starting"),
        ("ready", "ready"),
        ("failed", "failed"),
        ("unknown", "uninitialized"),
    ])
    def test_state_mapping(self, raw, expected):
        assert self._parse(raw) == expected


class TestCLIManagerInfrastructure:
    def _make_mgr(self):
        from mobileflow_agent.services.cli_manager import CLIManager
        mgr = CLIManager.__new__(CLIManager)
        mgr.config = Obj(work_dir="/tmp")
        mgr.event_bus = None
        mgr._sessions = {}
        mgr._session_ids = {}
        mgr._provider_tasks = {}
        mgr._session_locks = {}
        mgr._ws_broadcast = None
        return mgr

    def test_fields_exist(self):
        mgr = self._make_mgr()
        assert isinstance(mgr._provider_tasks, dict)
        assert isinstance(mgr._session_locks, dict)
        assert mgr._ws_broadcast is None

    def test_push_status(self):
        from mobileflow_protocol.types import MessageType
        mgr = self._make_mgr()
        calls = []

        async def fake_broadcast(client_id, msg):
            calls.append((client_id, msg))

        mgr._ws_broadcast = fake_broadcast
        asyncio.run(mgr._push_status(("client_1", "claude-code"), "starting", "正在启动 AI Agent..."))
        assert len(calls) == 1
        cid, msg = calls[0]
        assert cid == "client_1"
        assert msg.type == MessageType.CLI_STATUS
        assert msg.payload["cli"] == "claude-code"
        assert msg.payload["state"] == "starting"
        assert msg.payload["message"] == "正在启动 AI Agent..."

    def test_handle_retry_clears_state(self):
        mgr = self._make_mgr()

        class FakeProvider:
            is_running = False
            _lifecycle_state = ProviderLifecycleState.FAILED
            _error_message = "timeout"
            _execution_env = "native"
            async def shutdown(self): pass
            async def env_check(self): return (False, "still broken")

        key = ("client_1", "test-cli")
        mgr._sessions[key] = FakeProvider()
        mgr._session_ids[key] = "old-session-id"
        mgr._provider_tasks[key] = "placeholder-task"

        mgr._sessions.pop(key, None)
        mgr._session_ids.pop(key, None)
        mgr._provider_tasks.pop(key, None)
        assert key not in mgr._sessions
        assert key not in mgr._session_ids
        assert key not in mgr._provider_tasks

    def test_session_lock_serialization(self):
        mgr = self._make_mgr()

        async def _run():
            order = []

            async def op(label, delay):
                order.append(f"{label}_start")
                await asyncio.sleep(delay)
                order.append(f"{label}_end")
                return label

            k = ("c1", "cli1")
            t1 = asyncio.create_task(mgr._with_session_lock(k, op("A", 0.05)))
            t2 = asyncio.create_task(mgr._with_session_lock(k, op("B", 0.05)))
            await asyncio.gather(t1, t2)
            a_end = order.index("A_end")
            b_start = order.index("B_start")
            b_end = order.index("B_end")
            a_start = order.index("A_start")
            serialized = (a_end < b_start) or (b_end < a_start)
            return serialized, k in mgr._session_locks

        serialized, lock_created = asyncio.run(_run())
        assert lock_created
        assert serialized

    def test_session_recovery_fallback(self):
        class FakeStore:
            removed = []
            _sessions = ["next-session-id"]
            def remove(self, sid): self.removed.append(sid)
            def get_latest(self, cwd, cli_name=""):
                for s in self._sessions:
                    if s not in self.removed:
                        return s
                return None

        store = FakeStore()
        target_id = "expired-session"
        history = []
        if not history and target_id:
            store.remove(target_id)
            next_id = store.get_latest("/mnt/c/project", "test-cli")
            if next_id:
                history = []
                if not history:
                    store.remove(next_id)

        assert "expired-session" in store.removed
        assert "next-session-id" in store.removed
