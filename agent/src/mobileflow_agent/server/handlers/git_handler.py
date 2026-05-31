"""Git operations handler.

Module: server/handlers/
Responsibility:
    Handle all Git-related WebSocket messages (status, diff, stage, commit,
    push, pull, branches, checkout, log, discard, repo discovery, and
    arbitrary git command execution).

    Read operations (status, branches, log) return cached state from
    GitStateManager (<1ms). Write operations (commit, stage, push) go
    through GitStateManager.run() which automatically refreshes state
    after completion.

Dependencies:
    GitService (accessed via ``server.git_service``).
    GitStateManager (accessed via ``server.git_state``).
"""

from __future__ import annotations

import asyncio
from pathlib import Path

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.errors import PayloadValidationError
from mobileflow_protocol.payloads.git import (
    GitCheckoutPayload,
    GitCommitPayload,
    GitDiffCommitPayload,
    GitDiffPayload,
    GitDiscardPayload,
    GitExecPayload,
    GitLogAuthorsResultPayload,
    GitLogPayload,
    GitLogSearchPayload,
    GitReposPayload,
    GitReposResultPayload,
    GitShowPayload,
    GitStagePayload,
    GitStatusResultPayload,
    GitSwitchRepoPayload,
    GitUnstagePayload,
)
from mobileflow_protocol.types import MessageType

from ...utils.i18n import t
from .base import BaseHandler
from ...utils.operation import Op


class GitHandler(BaseHandler):
    """Handles Git operations over WebSocket.

    Maintains an optional ``_active_repo_path`` that overrides the default
    working directory when the user switches between discovered repositories.

    Attributes:
        _active_repo_path: User-selected repository path, or empty string
            to use the default working directory.
    """

    # User-selected active repository path (set via switch_repo)
    _active_repo_path: str = ""

    def reset_active_repo(self):
        """Clear the user-selected repository path.

        Called by ProjectHandler on project switch to prevent stale
        repo selection from carrying over to the new project.
        """
        self._active_repo_path = ""

    @property
    def git(self):
        """Shortcut to the Git service."""
        return self.server.git_service

    @property
    def git_state(self):
        """Shortcut to the Git state manager."""
        return self.server.git_state

    def _sync_cwd(self):
        """Synchronise the Git service working directory to the active repository."""
        cwd = self._active_repo_path or self.config.work_dir
        self.git._update_cwd(cwd)

    async def handle_git_status(self, client_id, ws, msg):
        """Return the current Git status of the active repository.

        Always executes a real ``git status`` via throttled_status() to
        ensure the returned data reflects the actual repository state.
        External tools (IDE, CLI) may modify the repo without going
        through our handlers, so cached data can be stale.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        logger.debug(f"git.status: client={client_id[:8]}...")
        self._sync_cwd()

        # Refresh via throttled_status to avoid concurrent git status calls.
        # The throttler merges parallel requests (e.g. RefreshScheduler +
        # this handler) into at most one execution at a time.
        await self.git_state.throttled_status()
        await self.send(ws, Message(
            type=MessageType.GIT_STATUS_RESULT,
            payload=self.git_state.status or {"error": t("backend.gitStatusNotReady")}))

    async def handle_git_diff(self, client_id, ws, msg):
        """Return diff output for a single file or the entire repository.

        When ``path`` is provided, returns the diff for that specific file.
        Otherwise returns both unstaged and staged diffs for the whole repo.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``path`` and ``staged`` flag.
        """
        try:
            payload = msg.typed_payload(GitDiffPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.diff payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()
        if payload.path:
            result = await self.git.file_content_for_diff(payload.path, staged=payload.staged)
        else:
            unstaged = await self.git.diff_all(staged=False)
            staged_diff = await self.git.diff_all(staged=True)
            result = {
                "diff": unstaged.get("diff", ""),
                "staged": staged_diff.get("diff", ""),
                "error": unstaged.get("error", "") or staged_diff.get("error", ""),
            }
        await self.send(ws, Message(
            type=MessageType.GIT_DIFF_RESULT, payload=result))

    async def handle_git_stage(self, client_id, ws, msg):
        """Stage files (or all changes) for commit.

        Uses GitStateManager.run() for automatic state refresh after staging.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``paths`` list or ``all`` flag.
        """
        try:
            payload = msg.typed_payload(GitStagePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.stage payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()

        async def _do_stage():
            if payload.all:
                return await self.git.stage_all()
            return await self.git.stage(payload.paths)

        op = Op.StageAll if payload.all else Op.Stage
        result = await self.git_state.run(op, run_operation=_do_stage)

        await self.send(ws, Message(
            type=MessageType.GIT_STAGE_RESULT, payload=result))

    async def handle_git_unstage(self, client_id, ws, msg):
        """Unstage files (or all staged changes).

        Uses GitStateManager.run() for automatic state refresh.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``paths`` list or ``all`` flag.
        """
        try:
            payload = msg.typed_payload(GitUnstagePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.unstage payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()

        async def _do_unstage():
            if payload.all:
                return await self.git.unstage_all()
            return await self.git.unstage(payload.paths)

        op = Op.UnstageAll if payload.all else Op.Unstage
        result = await self.git_state.run(op, run_operation=_do_unstage)

        await self.send(ws, Message(
            type=MessageType.GIT_UNSTAGE_RESULT, payload=result))

    async def handle_git_commit(self, client_id, ws, msg):
        """Create a Git commit with the given message.

        Uses GitStateManager.run() for automatic state refresh after commit.
        Includes optimistic update: staged files are cleared immediately
        in the cached state before the real git status completes.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``message``.
        """
        try:
            payload = msg.typed_payload(GitCommitPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.commit payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()
        logger.info(f"git.commit: message={payload.message[:50]}")

        state = self.git_state
        def _optimistic():
            """Clear staged files in cached state (commit moves them to history)."""
            current = state.status
            if current:
                return {"status": {**current, "staged": []}}
            return None

        result = await state.run(
            Op.Commit,
            run_operation=lambda: self.git.commit(payload.message),
            get_optimistic=_optimistic,
        )

        await self.send(ws, Message(
            type=MessageType.GIT_COMMIT_RESULT, payload=result))

    async def handle_git_push(self, client_id, ws, msg):
        """Push commits to the remote.

        Uses GitStateManager.run() for automatic state refresh.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        self._sync_cwd()
        logger.info("git.push: 推送到远程")

        state = self.git_state
        result = await state.run(Op.Push, run_operation=self.git.push)

        if result.get("error"):
            logger.error(f"git.push 失败: {result['error']}")
        await self.send(ws, Message(
            type=MessageType.GIT_PUSH_RESULT, payload=result))

    async def handle_git_pull(self, client_id, ws, msg):
        """Pull changes from the remote.

        Uses GitStateManager.run() for automatic state refresh.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        self._sync_cwd()
        logger.info("git.pull: 拉取远程更新")

        state = self.git_state
        result = await state.run(Op.Pull, run_operation=self.git.pull)

        if result.get("error"):
            logger.error(f"git.pull 失败: {result['error']}")
        await self.send(ws, Message(
            type=MessageType.GIT_PULL_RESULT, payload=result))

    async def handle_git_branches(self, client_id, ws, msg):
        """List all branches in the active repository.

        Returns cached state from GitStateManager if available.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        self._sync_cwd()

        state = self.git_state
        if state.branches is not None:
            await self.send(ws, Message(
                type=MessageType.GIT_BRANCHES_RESULT, payload=state.branches))
        else:
            result = await self.git.branches()
            await self.send(ws, Message(
                type=MessageType.GIT_BRANCHES_RESULT, payload=result))

    async def handle_git_checkout(self, client_id, ws, msg):
        """Check out a branch.

        Uses GitStateManager.run() for automatic state refresh.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``branch``.
        """
        try:
            payload = msg.typed_payload(GitCheckoutPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.checkout payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()
        logger.info(f"git.checkout: branch={payload.branch}")

        result = await self.git_state.run(
            Op.Checkout,
            run_operation=lambda: self.git.checkout(payload.branch),
        )

        await self.send(ws, Message(
            type=MessageType.GIT_CHECKOUT_RESULT, payload=result))

    async def handle_git_log(self, client_id, ws, msg):
        """Return the commit log.

        Returns cached state from GitStateManager if available.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``count`` (default 50).
        """
        try:
            payload = msg.typed_payload(GitLogPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.log payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()

        state = self.git_state
        if state.log_entries is not None:
            await self.send(ws, Message(
                type=MessageType.GIT_LOG_RESULT, payload=state.log_entries))
        else:
            result = await self.git.log(payload.count)
            await self.send(ws, Message(
                type=MessageType.GIT_LOG_RESULT, payload=result))

    async def handle_git_log_authors(self, client_id, ws, msg):
        """Return the list of unique commit authors for filter UI.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        self._sync_cwd()
        authors = await self.git.log_authors()
        await self.send(ws, Message.from_typed(
            type=MessageType.GIT_LOG_AUTHORS_RESULT,
            payload=GitLogAuthorsResultPayload(authors=authors),
        ))

    async def handle_git_log_search(self, client_id, ws, msg):
        """Unified git log query — search + filter + pagination in one call.

        All parameters are optional. When none are provided, returns the
        first page of the full log (same as git.log). Combines:
        - Text search (query → --grep)
        - Branch filter (branch)
        - Author filter (author → --author)
        - Date range (since/until → --since/--until)
        - Pagination (skip/count)

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``query``, ``branch``,
                 ``author``, ``since``, ``until``, ``skip``, ``count``.
        """
        try:
            payload = msg.typed_payload(GitLogSearchPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.log.search payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()
        logger.debug(f"git.log.search: query={payload.query!r}, branch={payload.branch!r}, "
                     f"author={payload.author!r}, since={payload.since!r}, skip={payload.skip}")
        result = await self.git.log(
            count=payload.count, skip=payload.skip, branch=payload.branch,
            author=payload.author, since=payload.since, until=payload.until,
            grep=payload.query,
        )
        await self.send(ws, Message(
            type=MessageType.GIT_LOG_SEARCH_RESULT, payload=result))

    async def handle_git_show(self, client_id, ws, msg):
        """Return commit details (metadata + changed files).

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``hash``.
        """
        try:
            payload = msg.typed_payload(GitShowPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.show payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()
        logger.debug(f"git.show: hash={payload.hash[:12]}")
        result = await self.git.show_commit(payload.hash)
        await self.send(ws, Message(
            type=MessageType.GIT_SHOW_RESULT, payload=result))

    async def handle_git_diff_commit(self, client_id, ws, msg):
        """Return old/new file content for a specific commit and file.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``hash`` and ``path``.
        """
        try:
            payload = msg.typed_payload(GitDiffCommitPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.diff.commit payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()
        logger.debug(f"git.diff.commit: hash={payload.hash[:12]}, path={payload.path}")
        result = await self.git.diff_commit_file(payload.hash, payload.path)
        await self.send(ws, Message(
            type=MessageType.GIT_DIFF_COMMIT_RESULT, payload=result))

    async def handle_git_discard(self, client_id, ws, msg):
        """Discard changes to a single file.

        Uses GitStateManager.run() for automatic state refresh.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path``.
        """
        try:
            payload = msg.typed_payload(GitDiscardPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.discard payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()

        result = await self.git_state.run(
            Op.Discard,
            run_operation=lambda: self.git.discard_file(payload.path),
        )

        await self.send(ws, Message(
            type=MessageType.GIT_DISCARD_RESULT, payload=result))

    async def handle_git_repos(self, client_id, ws, msg):
        """Discover all Git repositories under the working directory.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``max_depth`` (default 3).
        """
        try:
            payload = msg.typed_payload(GitReposPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.repos payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        logger.debug(f"git.repos: 扫描仓库, max_depth={payload.max_depth}")
        repos = await self.git.discover_repos(
            root_dir=self.config.work_dir, max_depth=payload.max_depth)
        # Override is_current using _active_repo_path when set.
        # discover_repos compares against GitService._cwd which is the
        # project root on first load — no repo matches. After the user
        # switches repos, _active_repo_path holds the selected repo path.
        if self._active_repo_path:
            resolved = str(Path(self._active_repo_path).resolve())
            for repo in repos:
                repo_path = str(Path(repo.get("path", "")).resolve())
                repo["is_current"] = repo_path == resolved
        logger.info(f"git.repos: 发现 {len(repos)} 个仓库")
        await self.send(ws, Message.from_typed(
            type=MessageType.GIT_REPOS_RESULT,
            payload=GitReposResultPayload(repos=repos),
        ))

    async def handle_git_switch_repo(self, client_id, ws, msg):
        """Switch the active Git repository and return its status.

        Clears cached state and triggers a full refresh for the new repo.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path`` (repository root).
        """
        try:
            payload = msg.typed_payload(GitSwitchRepoPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.switch_repo payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        if not payload.path:
            await self.send(ws, Message.from_typed(
                type=MessageType.GIT_STATUS_RESULT,
                payload=GitStatusResultPayload(error=t("backend.gitNoRepoSpecified"))))
            return
        self._active_repo_path = payload.path
        self.git._update_cwd(payload.path)
        logger.info(f"Git 仓库切换: {payload.path}")

        # Clear cached state for the old repo
        self.git_state.clear()

        # Fetch status directly from git (not from cache) for the new repo
        result = await self.git.status()
        await self.send(ws, Message(
            type=MessageType.GIT_STATUS_RESULT, payload=result.to_dict()))

        # Trigger async background refresh to populate full cache
        # (branches, log, etc.) without blocking the response
        asyncio.create_task(self.git_state.update_model_state())

    async def handle_git_exec(self, client_id, ws, msg):
        """Execute an arbitrary Git command with safety checks.

        Uses GitStateManager.run() so state is refreshed after write commands.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``command`` and optional ``confirmed`` flag.
        """
        try:
            payload = msg.typed_payload(GitExecPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ git.exec payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        self._sync_cwd()
        logger.debug(f"git.exec: command={payload.command}, confirmed={payload.confirmed}")

        async def _do_exec():
            result = await self.git.execute_command(payload.command)
            if result.get("dangerous") and payload.confirmed:
                cmd = result["command"]
                if cmd.startswith("git "):
                    cmd = cmd[4:]
                parts = cmd.split()
                out, err, code = await self.git._run(
                    *parts, timeout=self.config.git.command_timeout
                )
                return {
                    "success": code == 0, "stdout": out, "stderr": err,
                    "command": result["command"], "blocked": False,
                    "reason": "", "dangerous": False,
                }
            return result

        state = self.git_state
        result = await state.run(Op.GitCommand, run_operation=_do_exec)

        await self.send(ws, Message(
            type=MessageType.GIT_EXEC_RESULT, payload=result))
