"""Tests for ACP session resume feature.

Covers:
1. SessionStore history persistence (save/load/append/remove round-trips)
2. ACPProvider.resume_session (mocked ACP connection scenarios)
3. ChatHistoryResultPayload protocol extension (resumed field)
"""

import asyncio
import json
import sys

import pytest

sys.path.insert(0, "src")

from unittest.mock import AsyncMock, MagicMock, patch
from dataclasses import dataclass, field

from mobileflow_agent.services.session_store import SessionStore


# ── 1. SessionStore history persistence ──


class TestSessionStoreHistory:
    """Unit tests for SessionStore history persistence methods."""

    def test_save_and_load_history_round_trip(self, tmp_path):
        """save_history + load_history returns the same messages."""
        store = SessionStore(data_dir=tmp_path, max_history_messages=200)
        messages = [
            {"role": "user", "type": "text", "content": "Hello"},
            {"role": "assistant", "type": "text", "content": "Hi there!"},
        ]
        store.save_history("session-abc123", messages)
        loaded = store.load_history("session-abc123")
        assert loaded == messages

    def test_load_history_returns_empty_when_file_missing(self, tmp_path):
        """load_history returns [] when no history file exists."""
        store = SessionStore(data_dir=tmp_path, max_history_messages=200)
        result = store.load_history("nonexistent-session")
        assert result == []

    def test_load_history_returns_empty_and_deletes_corrupted_file(self, tmp_path):
        """load_history returns [] and deletes the file when it's corrupted."""
        store = SessionStore(data_dir=tmp_path, max_history_messages=200)
        # Create a corrupted history file
        history_dir = tmp_path / "history"
        history_dir.mkdir(parents=True, exist_ok=True)
        corrupted_file = history_dir / "corrupt-session.json"
        corrupted_file.write_text("not valid json {{{", encoding="utf-8")

        result = store.load_history("corrupt-session")
        assert result == []
        # File should be deleted after detecting corruption
        assert not corrupted_file.exists()

    def test_save_history_enforces_max_cap(self, tmp_path):
        """save_history keeps only the most recent max_history_messages."""
        cap = 5
        store = SessionStore(data_dir=tmp_path, max_history_messages=cap)
        messages = [{"role": "user", "content": f"msg-{i}"} for i in range(10)]
        store.save_history("capped-session", messages)
        loaded = store.load_history("capped-session")
        assert len(loaded) == cap
        # Should keep the most recent (last 5)
        assert loaded == messages[-cap:]

    def test_append_message_adds_to_existing_history(self, tmp_path):
        """append_message adds a message to existing history."""
        store = SessionStore(data_dir=tmp_path, max_history_messages=200)
        initial = [{"role": "user", "content": "first"}]
        store.save_history("append-session", initial)

        store.append_message("append-session", {"role": "assistant", "content": "second"})
        loaded = store.load_history("append-session")
        assert len(loaded) == 2
        assert loaded[0] == {"role": "user", "content": "first"}
        assert loaded[1] == {"role": "assistant", "content": "second"}

    def test_append_message_creates_new_file_if_none_exists(self, tmp_path):
        """append_message creates a new history file when none exists."""
        store = SessionStore(data_dir=tmp_path, max_history_messages=200)
        store.append_message("new-session", {"role": "user", "content": "hello"})
        loaded = store.load_history("new-session")
        assert loaded == [{"role": "user", "content": "hello"}]

    def test_remove_history_deletes_file(self, tmp_path):
        """remove_history deletes the history file."""
        store = SessionStore(data_dir=tmp_path, max_history_messages=200)
        store.save_history("remove-session", [{"role": "user", "content": "bye"}])
        # Verify file exists
        history_file = tmp_path / "history" / "remove-session.json"
        assert history_file.exists()

        store.remove_history("remove-session")
        assert not history_file.exists()
        # load_history should return empty after removal
        assert store.load_history("remove-session") == []

    def test_remove_history_noop_when_file_missing(self, tmp_path):
        """remove_history is a no-op when the file doesn't exist."""
        store = SessionStore(data_dir=tmp_path, max_history_messages=200)
        # Should not raise
        store.remove_history("never-existed-session")


# ── 2. ACPProvider.resume_session ──


@dataclass
class FakeCapabilities:
    """Minimal capabilities mock for testing resume_session guards."""
    supports_session_resume: bool = False
    supports_session_load: bool = False


class FakeClientImpl:
    """Minimal mock for ACPProvider._client_impl."""
    _work_dir: str = "/home/user/project"


class TestACPProviderResumeSession:
    """Unit tests for ACPProvider.resume_session with mocked connection."""

    def _make_provider(self, supports_resume=True, conn=None):
        """Create a minimal ACPProvider-like object for testing resume_session.

        We import and instantiate the real ACPProvider but patch internal state
        to avoid needing a real ACP process.
        """
        from mobileflow_agent.providers.acp_provider import ACPProvider

        provider = ACPProvider(
            command="fake-cli",
            args=[],
            execution_env="native",
        )
        provider._capabilities = FakeCapabilities(supports_session_resume=supports_resume)
        provider._conn = conn
        provider._client_impl = FakeClientImpl()
        provider._session_id = None
        return provider

    @pytest.mark.asyncio
    async def test_returns_false_when_resume_not_supported(self):
        """resume_session returns False when supports_session_resume is False."""
        provider = self._make_provider(supports_resume=False, conn=MagicMock())
        result = await provider.resume_session("session-123")
        assert result is False

    @pytest.mark.asyncio
    async def test_returns_false_when_conn_is_none(self):
        """resume_session returns False when _conn is None."""
        provider = self._make_provider(supports_resume=True, conn=None)
        result = await provider.resume_session("session-123")
        assert result is False

    @pytest.mark.asyncio
    async def test_returns_true_and_sets_session_id_on_success(self):
        """resume_session returns True and sets _session_id on success."""
        mock_conn = MagicMock()
        mock_conn.resume_session = AsyncMock(return_value=None)
        provider = self._make_provider(supports_resume=True, conn=mock_conn)

        result = await provider.resume_session("session-xyz-456")
        assert result is True
        assert provider._session_id == "session-xyz-456"
        mock_conn.resume_session.assert_called_once()

    @pytest.mark.asyncio
    async def test_returns_false_on_timeout(self):
        """resume_session returns False on asyncio.TimeoutError."""
        mock_conn = MagicMock()

        async def slow_resume(**kwargs):
            await asyncio.sleep(100)

        mock_conn.resume_session = slow_resume
        provider = self._make_provider(supports_resume=True, conn=mock_conn)

        # Patch asyncio.wait_for to raise TimeoutError immediately
        with patch("mobileflow_agent.providers.acp_provider.asyncio.wait_for",
                   side_effect=asyncio.TimeoutError()):
            result = await provider.resume_session("session-timeout")

        assert result is False
        assert provider._session_id is None

    @pytest.mark.asyncio
    async def test_returns_false_on_attribute_error(self):
        """resume_session returns False when SDK doesn't have the method."""
        mock_conn = MagicMock()
        # Simulate SDK not having resume_session by raising AttributeError
        mock_conn.resume_session = MagicMock(side_effect=AttributeError("no such method"))
        provider = self._make_provider(supports_resume=True, conn=mock_conn)

        # Patch wait_for to propagate the AttributeError
        with patch("mobileflow_agent.providers.acp_provider.asyncio.wait_for",
                   side_effect=AttributeError("no such method")):
            result = await provider.resume_session("session-no-method")

        assert result is False
        assert provider._session_id is None

    @pytest.mark.asyncio
    async def test_returns_false_on_generic_exception(self):
        """resume_session returns False on any generic exception."""
        mock_conn = MagicMock()
        mock_conn.resume_session = AsyncMock(side_effect=RuntimeError("connection lost"))
        provider = self._make_provider(supports_resume=True, conn=mock_conn)

        # Patch wait_for to propagate the RuntimeError
        with patch("mobileflow_agent.providers.acp_provider.asyncio.wait_for",
                   side_effect=RuntimeError("connection lost")):
            result = await provider.resume_session("session-error")

        assert result is False
        assert provider._session_id is None


# ── 3. Protocol payload ──


class TestChatHistoryResultPayload:
    """Unit tests for ChatHistoryResultPayload resumed field."""

    def test_payload_includes_resumed_field(self):
        """ChatHistoryResultPayload has a resumed field."""
        # Import from protocol package
        sys.path.insert(0, "../protocol/src")
        from mobileflow_protocol.payloads.chat import ChatHistoryResultPayload

        payload = ChatHistoryResultPayload(
            messages=[{"role": "user", "content": "hi"}],
            total=1,
            has_more=False,
            cli="test-cli",
            resumed=True,
        )
        assert payload.resumed is True

    def test_payload_resumed_defaults_to_false(self):
        """ChatHistoryResultPayload.resumed defaults to False."""
        sys.path.insert(0, "../protocol/src")
        from mobileflow_protocol.payloads.chat import ChatHistoryResultPayload

        payload = ChatHistoryResultPayload(
            messages=[],
            total=0,
            has_more=False,
            cli="test-cli",
        )
        assert payload.resumed is False
