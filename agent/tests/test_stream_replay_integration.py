"""Stream replay integration tests — simulates real user chat + disconnect flows.

Tests the full pipeline: ChatHandler + StreamReplay + WebSocket mock,
verifying that chunks are buffered, ws.send failures don't kill the
AI loop, and reconnecting clients receive replayed output.

Scenarios modeled after real user behavior:
  1. Normal chat (no disconnect) — chunks sent AND buffered.
  2. User locks phone mid-stream — ws.send fails, AI continues, buffer fills.
  3. User comes back after AI finishes — replay includes all chunks + done.
  4. User reconnects while AI still running — replay + live stream resumes.
  5. User cancels — buffer cleared.
  6. Long task with buffer overflow — recent chunks preserved.
  7. Multiple disconnect/reconnect cycles in one turn.

# Feature: stream-replay-disconnect-recovery
"""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.models import StreamChunk, StreamChunkType
from mobileflow_protocol.types import MessageType

from mobileflow_agent.server.handlers.chat_handler import ChatHandler
from mobileflow_agent.server.stream_replay import StreamReplay


# ═══════════════════════════════════════════════════════════════
# Fixtures
# ═══════════════════════════════════════════════════════════════


def _make_stream_chunks(n: int, prefix: str = "word") -> list[StreamChunk]:
    """Create N text StreamChunks for testing."""
    return [
        StreamChunk(type=StreamChunkType.TEXT, content=f"{prefix}-{i} ")
        for i in range(n)
    ]


def _make_tool_chunks() -> list[StreamChunk]:
    """Create a realistic tool call sequence."""
    return [
        StreamChunk(type=StreamChunkType.TEXT, content="I'll edit the file.\n"),
        StreamChunk(type=StreamChunkType.TOOL_USE, content="write_file",
                    tool_id="tc_001", status="running"),
        StreamChunk(type=StreamChunkType.TOOL_UPDATE, content="write_file",
                    tool_id="tc_001", status="completed"),
        StreamChunk(type=StreamChunkType.DIFF, content="",
                    file_path="src/main.py",
                    old_content="old code", new_content="new code"),
        StreamChunk(type=StreamChunkType.TEXT, content="Done!\n"),
    ]


@pytest.fixture
def replay():
    """Create a StreamReplay with default settings."""
    return StreamReplay(max_chunks=500)


@pytest.fixture
def small_replay():
    """Create a StreamReplay with small buffer for overflow tests."""
    return StreamReplay(max_chunks=10)


@pytest.fixture
def mock_server(replay):
    """Create a minimal mock WebSocketServer for ChatHandler."""
    server = MagicMock()
    server.config = MagicMock()
    server.config.default_cli = "test-cli"
    server.config.work_dir = "/tmp/test-project"
    server.config.attachments = MagicMock()
    server.config.attachments.max_image_size_mb = 5
    server.config.attachments.max_audio_size_mb = 10
    server.config.context = MagicMock()
    server.cli_manager = MagicMock()
    server.file_service = MagicMock()
    server.git_service = MagicMock()
    server.get_stream_replay = MagicMock(return_value=replay)
    return server


@pytest.fixture
def handler(mock_server):
    """Create a ChatHandler with mocked server."""
    return ChatHandler(mock_server)


@pytest.fixture
def ws_connected():
    """Mock WebSocket that succeeds on send (client connected)."""
    ws = AsyncMock()
    ws.send = AsyncMock()
    return ws


@pytest.fixture
def ws_disconnected():
    """Mock WebSocket that fails on send (client disconnected)."""
    ws = AsyncMock()
    ws.send = AsyncMock(side_effect=ConnectionError("WebSocket closed"))
    return ws


def _make_msg(message: str = "hello", cli: str = "test-cli") -> Message:
    """Create a chat.send Message."""
    return Message(type=MessageType.CHAT_SEND, payload={
        "message": message, "cli": cli,
    })


# ═══════════════════════════════════════════════════════════════
# Scenario 1: Normal chat (no disconnect)
# ═══════════════════════════════════════════════════════════════


class TestNormalChat:
    """User sends message, AI responds, no disconnect. Chunks are both
    sent to the client AND buffered in StreamReplay."""

    @pytest.mark.asyncio
    async def test_chunks_sent_and_buffered(self, handler, ws_connected, replay):
        """All chunks reach the client and are also in the replay buffer."""
        chunks = _make_stream_chunks(5)

        async def fake_send_message(**kwargs):
            for c in chunks:
                yield c

        handler.cli_manager.send_message = fake_send_message

        await handler.handle_chat_send("client-1", ws_connected, _make_msg())

        # ws.send called for each chunk + chat.done
        assert ws_connected.send.call_count == 6  # 5 chunks + 1 done

        # Replay buffer has all chunks + done
        assert replay.buffered_count == 6
        assert replay.is_finished
        assert not replay.is_active

    @pytest.mark.asyncio
    async def test_replay_available_after_normal_flow(self, handler, ws_connected, replay):
        """After a normal turn, replay.get_replay() returns all chunks."""
        chunks = _make_stream_chunks(3)

        async def fake_send_message(**kwargs):
            for c in chunks:
                yield c

        handler.cli_manager.send_message = fake_send_message

        await handler.handle_chat_send("client-1", ws_connected, _make_msg())

        replayed = replay.get_replay()
        assert len(replayed) == 4  # 3 text + 1 done

        # Verify chunk content is preserved
        first_chunk = replayed[0]["payload"]["chunk"]
        assert first_chunk["type"] == "text"
        assert first_chunk["content"] == "word-0 "


# ═══════════════════════════════════════════════════════════════
# Scenario 2: User locks phone mid-stream
# ═══════════════════════════════════════════════════════════════


class TestDisconnectMidStream:
    """User sends message, AI starts responding, user locks phone.
    WebSocket breaks. AI continues outputting. All chunks buffered."""

    @pytest.mark.asyncio
    async def test_ai_continues_after_disconnect(self, handler, ws_disconnected, replay):
        """ws.send fails but the AI loop continues — all chunks buffered."""
        chunks = _make_stream_chunks(10)

        async def fake_send_message(**kwargs):
            for c in chunks:
                yield c

        handler.cli_manager.send_message = fake_send_message

        await handler.handle_chat_send("client-1", ws_disconnected, _make_msg())

        # All chunks buffered despite send failures
        assert replay.buffered_count == 11  # 10 text + 1 done
        assert replay.is_finished

    @pytest.mark.asyncio
    async def test_tool_calls_buffered_on_disconnect(self, handler, ws_disconnected, replay):
        """Tool call chunks (write_file, diff) are preserved in buffer."""
        chunks = _make_tool_chunks()

        async def fake_send_message(**kwargs):
            for c in chunks:
                yield c

        handler.cli_manager.send_message = fake_send_message

        await handler.handle_chat_send("client-1", ws_disconnected, _make_msg())

        replayed = replay.get_replay()
        types = [r["payload"]["chunk"]["type"] for r in replayed[:-1]]  # exclude done
        assert types == ["text", "tool_use", "tool_update", "diff", "text"]

    @pytest.mark.asyncio
    async def test_partial_disconnect(self, handler, replay):
        """First 3 chunks sent OK, then disconnect, then 7 more buffered."""
        chunks = _make_stream_chunks(10)
        call_count = 0

        ws = AsyncMock()

        async def flaky_send(data):
            nonlocal call_count
            call_count += 1
            if call_count > 3:
                raise ConnectionError("WebSocket closed")

        ws.send = AsyncMock(side_effect=flaky_send)

        async def fake_send_message(**kwargs):
            for c in chunks:
                yield c

        handler.cli_manager.send_message = fake_send_message

        await handler.handle_chat_send("client-1", ws, _make_msg())

        # All 10 chunks + done are in the buffer regardless of send success
        assert replay.buffered_count == 11
        assert replay.is_finished

        # Reconnecting client can get chunks after seq 3 (what they already saw)
        missed = replay.get_replay(after_seq=3)
        assert len(missed) == 8  # chunks 4-10 + done


# ═══════════════════════════════════════════════════════════════
# Scenario 3: Reconnect after AI finishes
# ═══════════════════════════════════════════════════════════════


class TestReconnectAfterDone:
    """User comes back after AI finished. Replay includes everything."""

    @pytest.mark.asyncio
    async def test_replay_includes_done(self, handler, ws_disconnected, replay):
        """Replay buffer includes the chat.done message."""
        chunks = _make_stream_chunks(5)

        async def fake_send_message(**kwargs):
            for c in chunks:
                yield c

        handler.cli_manager.send_message = fake_send_message

        await handler.handle_chat_send("client-1", ws_disconnected, _make_msg())

        assert replay.is_finished
        replayed = replay.get_replay()
        last = replayed[-1]
        assert last["type"] == "chat.done"

    @pytest.mark.asyncio
    async def test_handle_chat_replay_returns_buffer(self, handler, replay):
        """handle_chat_replay sends buffered chunks to the reconnected client."""
        # Simulate a completed turn in the buffer
        replay.begin_turn(cli_name="test-cli")
        for i in range(5):
            replay.push({"type": "chat.stream", "payload": {"chunk": {"type": "text", "content": f"w{i}"}}})
        replay.push({"type": "chat.done", "payload": {}})
        replay.finish_turn(done_payload={"type": "chat.done", "payload": {}})

        ws = AsyncMock()
        msg = Message(type=MessageType.CHAT_REPLAY, payload={"after_seq": 0})

        await handler.handle_chat_replay("client-1", ws, msg)

        # Should have sent one CHAT_REPLAY_RESULT message
        ws.send.assert_called_once()
        sent_raw = ws.send.call_args[0][0]
        import json
        sent = json.loads(sent_raw)
        assert sent["type"] == "chat.replay.result"
        assert len(sent["payload"]["chunks"]) == 6  # 5 text + 1 done
        assert sent["payload"]["streaming"] is False

    @pytest.mark.asyncio
    async def test_handle_chat_replay_with_after_seq(self, handler, replay):
        """Replay respects after_seq — only sends chunks the client missed."""
        replay.begin_turn()
        for i in range(10):
            replay.push({"type": "chat.stream", "id": i})
        replay.finish_turn()

        ws = AsyncMock()
        # Client already saw first 5 chunks
        msg = Message(type=MessageType.CHAT_REPLAY, payload={"after_seq": 5})

        await handler.handle_chat_replay("client-1", ws, msg)

        import json
        sent = json.loads(ws.send.call_args[0][0])
        assert len(sent["payload"]["chunks"]) == 5  # chunks 6-10


# ═══════════════════════════════════════════════════════════════
# Scenario 4: Cancel clears buffer
# ═══════════════════════════════════════════════════════════════


class TestCancelClearsBuffer:
    """User cancels mid-stream. Buffer should be cleared."""

    @pytest.mark.asyncio
    async def test_cancel_clears_replay(self, handler, replay):
        """handle_chat_cancel clears the StreamReplay buffer."""
        # Simulate active turn with some chunks
        replay.begin_turn(cli_name="test-cli")
        for i in range(5):
            replay.push({"type": "chat.stream"})

        assert replay.is_active
        assert replay.buffered_count == 5

        ws = AsyncMock()
        handler.cli_manager.cancel_current = AsyncMock()
        handler.server._permission_futures = {}

        msg = Message(type=MessageType.CHAT_CANCEL, payload={"cli": "test-cli"})
        await handler.handle_chat_cancel("client-1", ws, msg)

        # Buffer should be cleared
        assert replay.buffered_count == 0
        assert not replay.is_active
        assert not replay.is_finished


# ═══════════════════════════════════════════════════════════════
# Scenario 5: Long task with buffer overflow
# ═══════════════════════════════════════════════════════════════


class TestLongTaskOverflow:
    """AI runs for hours, generates thousands of chunks. Buffer overflows.
    User reconnects and gets the most recent output."""

    @pytest.mark.asyncio
    async def test_overflow_preserves_recent(self, handler, small_replay):
        """With max_chunks=10, only the last 10 chunks are kept."""
        handler.server.get_stream_replay = MagicMock(return_value=small_replay)

        chunks = _make_stream_chunks(50)

        async def fake_send_message(**kwargs):
            for c in chunks:
                yield c

        handler.cli_manager.send_message = fake_send_message

        ws = AsyncMock()
        ws.send = AsyncMock(side_effect=ConnectionError("disconnected"))

        await handler.handle_chat_send("client-1", ws, _make_msg())

        # Buffer capped at 10 (max_chunks)
        assert small_replay.buffered_count == 10

        # Should contain the most recent chunks (including done)
        replayed = small_replay.get_replay()
        assert len(replayed) == 10
        # Last entry should be chat.done
        assert replayed[-1]["type"] == "chat.done"


# ═══════════════════════════════════════════════════════════════
# Scenario 6: New turn clears previous buffer
# ═══════════════════════════════════════════════════════════════


class TestNewTurnClearsPrevious:
    """User sends a second message. Previous turn's buffer is cleared."""

    @pytest.mark.asyncio
    async def test_second_turn_clears_first(self, handler, ws_connected, replay):
        """begin_turn() on second message clears first turn's buffer."""
        # Turn 1
        async def turn1(**kwargs):
            yield StreamChunk(type=StreamChunkType.TEXT, content="turn1")

        handler.cli_manager.send_message = turn1
        await handler.handle_chat_send("client-1", ws_connected, _make_msg("first"))

        assert replay.buffered_count == 2  # 1 text + 1 done
        assert replay.is_finished

        # Turn 2 — begin_turn clears turn 1
        async def turn2(**kwargs):
            yield StreamChunk(type=StreamChunkType.TEXT, content="turn2")

        handler.cli_manager.send_message = turn2
        await handler.handle_chat_send("client-1", ws_connected, _make_msg("second"))

        assert replay.buffered_count == 2  # only turn 2 chunks
        replayed = replay.get_replay()
        assert replayed[0]["payload"]["chunk"]["content"] == "turn2"


# ═══════════════════════════════════════════════════════════════
# Scenario 7: Error during AI response
# ═══════════════════════════════════════════════════════════════


class TestErrorDuringStream:
    """AI throws an error mid-stream. Buffer should be finalized."""

    @pytest.mark.asyncio
    async def test_error_finalizes_replay(self, handler, ws_connected, replay):
        """Exception in send_message still finalizes the replay buffer."""
        async def failing_send(**kwargs):
            yield StreamChunk(type=StreamChunkType.TEXT, content="partial")
            raise RuntimeError("ACP connection lost")

        handler.cli_manager.send_message = failing_send

        await handler.handle_chat_send("client-1", ws_connected, _make_msg())

        # Replay should be finalized (not left in active state)
        assert not replay.is_active
