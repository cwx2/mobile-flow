"""
Unified diff path feasibility tests (migrated to pytest).

Covers: serialization performance, WebSocket payload size,
collector event ordering, path consistency, concurrent writes,
FILE_EDIT → StreamChunk conversion, SnapshotStore memory management.
"""

from __future__ import annotations

import asyncio
import json
import time
from pathlib import Path

import pytest

from mobileflow_agent.providers.acp_client import ACPEventCollector
from mobileflow_agent.providers.base import AgentEvent, AgentEventType


class TestSerializationPerformance:
    @pytest.mark.parametrize("line_count", [100, 1000, 5000, 10000])
    def test_serialize_speed(self, line_count):
        old = "\n".join(f"def function_{i}(): # line {i} - original" for i in range(line_count))
        new = "\n".join(f"def function_{i}(): # line {i} - modified" for i in range(line_count))
        chunk = {"type": "diff", "content": "", "file_path": f"file_{line_count}.py",
                 "old_content": old, "new_content": new}
        start = time.perf_counter()
        payload = json.dumps({"chunk": chunk}, ensure_ascii=False)
        ms = (time.perf_counter() - start) * 1000
        mb = len(payload.encode("utf-8")) / 1024 / 1024
        assert ms < 100, f"Serialization too slow: {ms:.2f}ms"
        assert mb < 10, f"Payload too large: {mb:.2f}MB"


class TestCollectorEventOrdering:
    @pytest.mark.asyncio
    async def test_event_order(self):
        collector = ACPEventCollector()
        events = [
            AgentEvent(type=AgentEventType.TOOL_CALL_START, data={"name": "Write to file", "kind": "edit", "id": "tool_1", "file_path": "main.py"}),
            AgentEvent(type=AgentEventType.FILE_EDIT, data={"path": "main.py", "full_old": "print('hello')", "full_new": "print('hello world')"}),
            AgentEvent(type=AgentEventType.TOOL_CALL_UPDATE, data={"id": "tool_1", "status": "completed"}),
            AgentEvent(type=AgentEventType.TEXT_CHUNK, data={"text": "I've updated main.py"}),
        ]
        for e in events:
            collector.put(e)
        received = []
        while not collector.events.empty():
            received.append(collector.events.get_nowait())
        assert len(received) == 4
        assert received[0].type == AgentEventType.TOOL_CALL_START
        assert received[1].type == AgentEventType.FILE_EDIT
        assert received[2].type == AgentEventType.TOOL_CALL_UPDATE
        assert received[3].type == AgentEventType.TEXT_CHUNK
        assert received[1].data["path"] == "main.py"


class TestPathConsistency:
    @pytest.mark.asyncio
    async def test_write_and_snapshot(self, tmp_path):
        from mobileflow_agent.providers.acp_client import ACPClientImpl
        collector = ACPEventCollector()
        client = ACPClientImpl(collector, event_bus=None)
        client.set_work_dir(str(tmp_path))
        test_file = tmp_path / "src" / "main.py"
        test_file.parent.mkdir(parents=True, exist_ok=True)
        test_file.write_text("old content", encoding="utf-8")
        result = await client.write_text_file("src/main.py", "new content")
        assert "error" not in result
        assert test_file.read_text(encoding="utf-8") == "new content"
        assert client._snapshots.get_initial_content("src/main.py") == "old content"


class TestConcurrentWrites:
    @pytest.mark.asyncio
    async def test_10_concurrent_writes(self, tmp_path):
        from mobileflow_agent.providers.acp_client import ACPClientImpl
        collector = ACPEventCollector()
        client = ACPClientImpl(collector, event_bus=None)
        client.set_work_dir(str(tmp_path))
        files = []
        for i in range(10):
            f = tmp_path / f"file_{i}.py"
            f.write_text(f"# original content {i}\n" * 100, encoding="utf-8")
            files.append(f"file_{i}.py")
        tasks = [client.write_text_file(p, f"# modified {i}\n" * 100) for i, p in enumerate(files)]
        results = await asyncio.gather(*tasks)
        errors = [r for r in results if "error" in r]
        assert len(errors) == 0
        for p in files:
            assert client._snapshots.get_initial_content(p) is not None


class TestEventToChunkConversion:
    def test_file_edit_to_stream_chunk(self):
        from mobileflow_agent.services.cli_manager import CLIManager
        event = AgentEvent(type=AgentEventType.FILE_EDIT, data={
            "path": "src/main.py",
            "full_old": "def hello():\n    print('hello')\n",
            "full_new": "def hello():\n    print('hello world')\n\ndef goodbye():\n    print('bye')\n",
        })
        chunk = CLIManager._event_to_chunk(event)
        assert chunk is not None
        assert chunk.type.value == "diff"
        assert chunk.file_path == "src/main.py"
        assert chunk.old_content == event.data["full_old"]
        assert chunk.new_content == event.data["full_new"]


class TestSnapshotMemory:
    def test_memory_limit(self):
        from mobileflow_agent.services.snapshot_store import SnapshotStore
        store = SnapshotStore()
        for i in range(50):
            store.capture_before_edit(f"file_{i}.py", f"# file {i}\n" * 1000)
        assert store.stats["memory_bytes"] < store.MAX_TOTAL_BYTES

    def test_hot_file_version_limit(self):
        from mobileflow_agent.services.snapshot_store import SnapshotStore
        store = SnapshotStore()
        for v in range(30):
            store.capture_before_edit("hot_file.py", f"# version {v}\n" * 1000)
        history = store.get_file_history("hot_file.py")
        assert history.version_count <= store.MAX_VERSIONS_PER_FILE
