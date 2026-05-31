"""Stream replay buffer tests — simulates real user disconnect/reconnect scenarios.

Tests cover:
  1. Normal flow (no disconnect): chunks buffered + sent, replay available.
  2. Disconnect mid-stream: AI continues, chunks buffered, replay on reconnect.
  3. Disconnect + AI finishes: replay includes done signal.
  4. Long task with buffer overflow: oldest chunks dropped, recent preserved.
  5. Cancel clears buffer.
  6. New turn clears previous buffer.
  7. Replay with after_seq filtering.
  8. Multiple disconnect/reconnect cycles.

# Feature: stream-replay-disconnect-recovery
"""

from __future__ import annotations

import asyncio
import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from mobileflow_agent.server.stream_replay import StreamReplay


# ═══════════════════════════════════════════════════════════════
# Unit tests for StreamReplay buffer
# ═══════════════════════════════════════════════════════════════


class TestStreamReplayBasic:
    """Basic buffer operations."""

    def test_empty_buffer(self):
        """Fresh buffer has no chunks and is not active."""
        replay = StreamReplay(max_chunks=100)
        assert replay.buffered_count == 0
        assert replay.seq == 0
        assert not replay.is_active
        assert not replay.is_finished
        assert replay.get_replay() == []

    def test_begin_turn_activates(self):
        """begin_turn sets active state and clears previous data."""
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn(cli_name="test-cli")
        assert replay.is_active
        assert not replay.is_finished
        assert replay.seq == 0

    def test_push_increments_seq(self):
        """Each push increments the sequence number."""
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn()

        seq1 = replay.push({"type": "chat.stream", "payload": {"chunk": {"type": "text", "content": "hello"}}})
        seq2 = replay.push({"type": "chat.stream", "payload": {"chunk": {"type": "text", "content": " world"}}})

        assert seq1 == 1
        assert seq2 == 2
        assert replay.seq == 2
        assert replay.buffered_count == 2

    def test_finish_turn_deactivates(self):
        """finish_turn marks the turn as complete with cached done payload."""
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn()
        replay.push({"type": "chat.stream"})
        replay.finish_turn(done_payload={"type": "chat.done", "payload": {}})

        assert not replay.is_active
        assert replay.is_finished
        assert replay.done_payload == {"type": "chat.done", "payload": {}}

    def test_clear_resets_everything(self):
        """clear() resets all state."""
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn()
        replay.push({"type": "chat.stream"})
        replay.clear()

        assert replay.buffered_count == 0
        assert replay.seq == 0
        assert not replay.is_active
        assert not replay.is_finished


class TestStreamReplayOverflow:
    """Ring buffer overflow behavior."""

    def test_oldest_chunks_dropped_on_overflow(self):
        """When buffer is full, oldest chunks are silently dropped."""
        replay = StreamReplay(max_chunks=5)
        replay.begin_turn()

        # Push 8 chunks into a buffer of size 5
        for i in range(8):
            replay.push({"id": i, "content": f"chunk-{i}"})

        assert replay.buffered_count == 5
        assert replay.seq == 8

        # Only the last 5 should remain (chunks 3-7)
        chunks = replay.get_replay()
        assert len(chunks) == 5
        assert chunks[0]["id"] == 3
        assert chunks[4]["id"] == 7

    def test_replay_after_seq_with_overflow(self):
        """after_seq filtering works correctly after overflow."""
        replay = StreamReplay(max_chunks=5)
        replay.begin_turn()

        for i in range(8):
            replay.push({"id": i})

        # Request chunks after seq 5 (should get chunks 6, 7, 8)
        chunks = replay.get_replay(after_seq=5)
        assert len(chunks) == 3


class TestStreamReplayScenarios:
    """Real user scenarios."""

    def test_scenario_normal_flow(self):
        """Scenario: User sends message, AI responds, no disconnect.

        All chunks are buffered AND sent. Buffer is available for
        potential replay but not needed.
        """
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn(cli_name="claude-code")

        # Simulate 10 text chunks
        for i in range(10):
            replay.push({
                "type": "chat.stream",
                "payload": {"chunk": {"type": "text", "content": f"word{i} "}},
            })

        # AI finishes
        done = {"type": "chat.done", "payload": {}}
        replay.push(done)
        replay.finish_turn(done_payload=done)

        assert replay.buffered_count == 11  # 10 text + 1 done
        assert replay.is_finished
        assert not replay.is_active

    def test_scenario_disconnect_mid_stream(self):
        """Scenario: User sends message, AI starts responding, user locks phone.

        WebSocket breaks. AI continues. User unlocks phone, reconnects.
        Should see recent output via replay.
        """
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn(cli_name="kiro-cli")

        # Phase 1: 5 chunks sent successfully (before disconnect)
        sent_count = 0
        for i in range(5):
            replay.push({
                "type": "chat.stream",
                "payload": {"chunk": {"type": "text", "content": f"sent-{i} "}},
            })
            sent_count += 1

        last_sent_seq = sent_count  # App received up to seq 5

        # Phase 2: disconnect — 20 more chunks buffered but not sent
        for i in range(20):
            replay.push({
                "type": "chat.stream",
                "payload": {"chunk": {"type": "text", "content": f"missed-{i} "}},
            })

        # AI still running
        assert replay.is_active
        assert replay.buffered_count == 25

        # Phase 3: reconnect — App requests replay after seq 5
        missed_chunks = replay.get_replay(after_seq=last_sent_seq)
        assert len(missed_chunks) == 20
        assert missed_chunks[0]["payload"]["chunk"]["content"] == "missed-0 "

    def test_scenario_disconnect_ai_finishes(self):
        """Scenario: User locks phone, AI finishes the entire task.

        User comes back, should see all output + done signal.
        """
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn(cli_name="claude-code")

        # 3 chunks sent before disconnect
        for i in range(3):
            replay.push({"type": "chat.stream", "id": f"sent-{i}"})

        # Disconnect happens here. 50 more chunks + done
        for i in range(50):
            replay.push({"type": "chat.stream", "id": f"missed-{i}"})

        done = {"type": "chat.done", "payload": {}}
        replay.push(done)
        replay.finish_turn(done_payload=done)

        assert replay.is_finished
        assert not replay.is_active

        # Reconnect — get everything after seq 3
        chunks = replay.get_replay(after_seq=3)
        assert len(chunks) == 51  # 50 stream + 1 done
        assert chunks[-1]["type"] == "chat.done"

    def test_scenario_long_task_buffer_overflow(self):
        """Scenario: AI runs for hours, generates thousands of chunks.

        Buffer overflows. User reconnects. Gets the most recent output
        (last N chunks), not the beginning.
        """
        replay = StreamReplay(max_chunks=50)
        replay.begin_turn(cli_name="kiro-cli")

        # Simulate 2000 chunks (hours of output)
        for i in range(2000):
            replay.push({
                "type": "chat.stream",
                "payload": {"chunk": {"type": "text", "content": f"line-{i}\n"}},
            })

        assert replay.is_active
        assert replay.buffered_count == 50  # Only last 50 kept
        assert replay.seq == 2000

        # Reconnect — get all available (last 50)
        chunks = replay.get_replay()
        assert len(chunks) == 50
        # Should be the most recent chunks (1950-1999)
        assert chunks[0]["payload"]["chunk"]["content"] == "line-1950\n"
        assert chunks[-1]["payload"]["chunk"]["content"] == "line-1999\n"

    def test_scenario_cancel_clears_buffer(self):
        """Scenario: User cancels mid-stream. Buffer should be cleared.

        Cancelled output is not useful for replay.
        """
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn(cli_name="claude-code")

        for i in range(10):
            replay.push({"type": "chat.stream", "id": i})

        # User cancels
        replay.clear()

        assert replay.buffered_count == 0
        assert not replay.is_active
        assert not replay.is_finished

    def test_scenario_new_turn_clears_previous(self):
        """Scenario: AI finishes turn 1. User sends new message (turn 2).

        Turn 1 buffer should be cleared when turn 2 begins.
        """
        replay = StreamReplay(max_chunks=100)

        # Turn 1
        replay.begin_turn(cli_name="claude-code")
        for i in range(10):
            replay.push({"type": "chat.stream", "id": f"turn1-{i}"})
        replay.finish_turn(done_payload={"type": "chat.done"})

        assert replay.buffered_count == 10

        # Turn 2 — should clear turn 1 data
        replay.begin_turn(cli_name="claude-code")
        assert replay.buffered_count == 0
        assert replay.seq == 0
        assert replay.is_active
        assert not replay.is_finished

    def test_scenario_multiple_reconnects(self):
        """Scenario: User reconnects multiple times during a long task.

        Each reconnect should get chunks from where they left off.
        """
        replay = StreamReplay(max_chunks=200)
        replay.begin_turn(cli_name="kiro-cli")

        # Phase 1: 30 chunks, client connected
        for i in range(30):
            replay.push({"id": i})
        client_seq = 30

        # Phase 2: disconnect, 20 more chunks
        for i in range(30, 50):
            replay.push({"id": i})

        # Reconnect 1: get chunks 31-50
        missed = replay.get_replay(after_seq=client_seq)
        assert len(missed) == 20
        client_seq = replay.seq  # 50

        # Phase 3: connected again, 10 more chunks
        for i in range(50, 60):
            replay.push({"id": i})
        client_seq = replay.seq  # 60

        # Phase 4: disconnect again, 15 more chunks
        for i in range(60, 75):
            replay.push({"id": i})

        # Reconnect 2: get chunks 61-75
        missed = replay.get_replay(after_seq=client_seq)
        assert len(missed) == 15
        assert missed[0]["id"] == 60
        assert missed[-1]["id"] == 74

    def test_scenario_tool_calls_in_replay(self):
        """Scenario: AI uses tools (file edits, shell commands) during disconnect.

        Tool call chunks should be preserved in the replay buffer
        so the user sees what the AI did.
        """
        replay = StreamReplay(max_chunks=100)
        replay.begin_turn(cli_name="claude-code")

        # Text chunk
        replay.push({"type": "chat.stream", "payload": {"chunk": {
            "type": "text", "content": "I'll edit the file...\n",
        }}})

        # Tool call start
        replay.push({"type": "chat.stream", "payload": {"chunk": {
            "type": "tool_use", "content": "write_file",
            "tool_id": "tc_001", "status": "running",
        }}})

        # Tool call update (completed)
        replay.push({"type": "chat.stream", "payload": {"chunk": {
            "type": "tool_update", "tool_id": "tc_001",
            "status": "completed",
        }}})

        # Diff chunk
        replay.push({"type": "chat.stream", "payload": {"chunk": {
            "type": "diff", "file_path": "src/main.py",
            "old_content": "old", "new_content": "new",
        }}})

        # More text
        replay.push({"type": "chat.stream", "payload": {"chunk": {
            "type": "text", "content": "Done! The file has been updated.\n",
        }}})

        assert replay.buffered_count == 5

        # Replay all — should preserve all chunk types
        chunks = replay.get_replay()
        types = [c["payload"]["chunk"]["type"] for c in chunks]
        assert types == ["text", "tool_use", "tool_update", "diff", "text"]
