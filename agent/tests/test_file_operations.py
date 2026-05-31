"""
文件操作单元测试
覆盖 FileService 的 create_file / rename_file / delete_file 和搜索增强
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from mobileflow_agent.core.config import AgentConfig
from mobileflow_agent.services.file_service import FileService


@pytest.fixture
def svc(tmp_path):
    """创建一个以 tmp_path 为工作目录的 FileService"""
    config = AgentConfig(work_dir=str(tmp_path))
    return FileService(config)


# ── create_file ──

class TestCreateFile:
    def test_create_file(self, svc, tmp_path):
        result = svc.create_file("", "hello.txt", "file")
        assert result["success"] is True
        assert (tmp_path / "hello.txt").exists()

    def test_create_dir(self, svc, tmp_path):
        result = svc.create_file("", "subdir", "dir")
        assert result["success"] is True
        assert (tmp_path / "subdir").is_dir()

    def test_create_existing_file(self, svc, tmp_path):
        (tmp_path / "dup.txt").touch()
        result = svc.create_file("", "dup.txt", "file")
        assert result["success"] is False
        assert "已存在" in result["error"]

    def test_create_existing_dir(self, svc, tmp_path):
        (tmp_path / "dup_dir").mkdir()
        result = svc.create_file("", "dup_dir", "dir")
        assert result["success"] is False
        assert "已存在" in result["error"]

    def test_create_path_traversal(self, svc):
        result = svc.create_file("../../etc", "passwd", "file")
        assert result["success"] is False


# ── rename_file ──

class TestRenameFile:
    def test_rename(self, svc, tmp_path):
        (tmp_path / "old.txt").write_text("data")
        result = svc.rename_file("old.txt", "new.txt")
        assert result["success"] is True
        assert not (tmp_path / "old.txt").exists()
        assert (tmp_path / "new.txt").exists()

    def test_rename_target_exists(self, svc, tmp_path):
        (tmp_path / "a.txt").touch()
        (tmp_path / "b.txt").touch()
        result = svc.rename_file("a.txt", "b.txt")
        assert result["success"] is False
        assert "已存在" in result["error"]

    def test_rename_not_found(self, svc):
        result = svc.rename_file("ghost.txt", "new.txt")
        assert result["success"] is False
        assert "不存在" in result["error"]


# ── delete_file ──

class TestDeleteFile:
    def test_delete_file(self, svc, tmp_path):
        (tmp_path / "bye.txt").touch()
        result = svc.delete_file("bye.txt")
        assert result["success"] is True
        assert not (tmp_path / "bye.txt").exists()

    def test_delete_dir(self, svc, tmp_path):
        d = tmp_path / "rmdir"
        d.mkdir()
        (d / "child.txt").touch()
        result = svc.delete_file("rmdir")
        assert result["success"] is True
        assert not d.exists()

    def test_delete_not_found(self, svc):
        result = svc.delete_file("nope.txt")
        assert result["success"] is False
        assert "不存在" in result["error"]


# ── search enhanced (context_before / context_after) ──

class TestSearchContext:
    @pytest.mark.asyncio
    async def test_content_search_with_context(self, svc, tmp_path):
        (tmp_path / "code.py").write_text("line1\ntarget_line\nline3\n")
        results = await svc.search("target_line", search_content=True)
        content_hits = [r for r in results if r["type"] == "content"]
        assert len(content_hits) >= 1
        hit = content_hits[0]
        assert hit["context_before"] == "line1"
        assert hit["context_after"] == "line3"

    @pytest.mark.asyncio
    async def test_first_line_match_no_before(self, svc, tmp_path):
        (tmp_path / "first.txt").write_text("match_here\nsecond\n")
        results = await svc.search("match_here", search_content=True)
        content_hits = [r for r in results if r["type"] == "content"]
        assert len(content_hits) >= 1
        hit = content_hits[0]
        assert hit["context_before"] == ""
        assert hit["context_after"] == "second"

    @pytest.mark.asyncio
    async def test_last_line_match_no_after(self, svc, tmp_path):
        (tmp_path / "last.txt").write_text("first\nmatch_end")
        results = await svc.search("match_end", search_content=True)
        content_hits = [r for r in results if r["type"] == "content"]
        assert len(content_hits) >= 1
        hit = content_hits[0]
        assert hit["context_before"] == "first"
        assert hit["context_after"] == ""
