"""Git operations handler - multi-repo architecture.

Module: server/handlers/
Responsibility:
    Handle all Git-related WebSocket messages. Every operation is routed
    to the correct repository via the ``repo`` field in the payload.
    No global "active repository" state exists.

    Architecture:
    - All repos managed by MultiRepoManager (independent GitStateManager per repo)
    - Read operations return cached state from per-repo GitStateManager
    - Write operations go through per-repo GitStateManager.run()
    - No shared mutable cwd - each repo has its own GitService instance

Dependencies:
    MultiRepoManager (accessed via ``server.multi_repo_manager``).
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
    GitConflictResolveAllPayload,
    GitConflictResolvePayload,
    GitConflictsPayload,
    GitDiffCommitPayload,
    GitDiffPayload,
    GitDiscardPayload,
    GitExecPayload,
    GitLogAuthorsResultPayload,
    GitLogPayload,
    GitLogSearchPayload,
    GitMergeAbortPayload,
    GitReposPayload,
    GitReposResultPayload,
    GitShowPayload,
    GitStagePayload,
    GitStatusResultPayload,
    GitUnstagePayload,
)
from mobileflow_protocol.types import MessageType

from ...utils.i18n import t
from .base import BaseHandler
from ...utils.operation import Op


class GitHandler(BaseHandler):
    """Handles Git operations over WebSocket (multi-repo, no global state).

    All operations route to a specific repository via payload.repo field.
    The MultiRepoManager holds independent GitStateManager instances per repo.
    """

    @property
    def multi_repo(self):
        """Shortcut to the multi-repo manager."""
        return self.server.multi_repo_manager

    def _get_repo_manager(self, repo_path: str):
        """Get the GitStateManager for a given repository path.

        Args:
            repo_path: Repository path from payload.repo field.

        Returns:
            Tuple of (GitStateManager, GitService) or (None, None).
        """
        if not repo_path:
            return None, None
        manager = self.multi_repo.get_manager(repo_path)
        if manager:
            return manager, manager._git
        return None, None

    async def _require_repo(self, ws, repo_path: str):
        """Validate repo field and return manager, or send error.

        Returns:
            Tuple of (GitStateManager, GitService) on success, or (None, None)
            after sending error response.
        """
        if not repo_path:
            await self.send_error(ws, t("backend.gitNoRepoSpecified"))
            return None, None
        manager, git = self._get_repo_manager(repo_path)
        if not manager:
            await self.send_error(ws, f"Repository not found: {repo_path}")
            return None, None
        return manager, git


    # -- Status (read) --

    async def handle_git_status_all(self, client_id, ws, msg):
        """Return aggregated status of all discovered repositories.

        Primary status endpoint. Refreshes all repos in parallel and
        returns a list of per-repo status snapshots.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        logger.info(f": client={client_id[:8]}...")
        multi_repo = self.multi_repo

        if multi_repo and multi_repo.repo_count > 0:
            await multi_repo.refresh_all()
            result = multi_repo.get_all_status()
        else:
            result = []

        await self.send(ws, Message(
            type=MessageType.GIT_STATUS_ALL_RESULT,
            payload={"repos": result}))

    async def handle_git_status(self, client_id, ws, msg):
        """Return status of a single repository (backward compat).

        If no repo is specified, redirects to status.all behavior.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``repo`` field.
        """
        logger.debug(f"git.status: client={client_id[:8]}...")

        # If multi-repo is active and no specific repo requested,
        # return the first repo's status for backward compatibility
        if self.multi_repo and self.multi_repo.repo_count > 0:
            # Try to get repo from payload if available
            repo_path = ""
            try:
                payload = msg.payload or {}
                repo_path = payload.get("repo", "")
            except Exception:
                pass

            if repo_path:
                manager, _ = self._get_repo_manager(repo_path)
                if manager:
                    await manager.throttled_status()
                    await self.send(ws, Message(
                        type=MessageType.GIT_STATUS_RESULT,
                        payload=manager.status or {"error": t("backend.gitStatusNotReady")}))
                    return

            # No specific repo -return first repo's status
            for manager in self.multi_repo.repos.values():
                await manager.throttled_status()
                await self.send(ws, Message(
                    type=MessageType.GIT_STATUS_RESULT,
                    payload=manager.status or {"error": t("backend.gitStatusNotReady")}))
                return

        await self.send(ws, Message(
            type=MessageType.GIT_STATUS_RESULT,
            payload={"error": t("backend.gitStatusNotReady")}))

    # -- Diff (read) --

    async def handle_git_diff(self, client_id, ws, msg):
        """Return diff output for a single file or the entire repository.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``path``, ``staged``, and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitDiffPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.diff payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        repo_path = getattr(payload, 'repo', '') or ''
        _, git = await self._require_repo(ws, repo_path)
        if not git:
            return

        if payload.path:
            result = await git.file_content_for_diff(payload.path, staged=payload.staged)
        else:
            unstaged = await git.diff_all(staged=False)
            staged_diff = await git.diff_all(staged=True)
            result = {
                "diff": unstaged.get("diff", ""),
                "staged": staged_diff.get("diff", ""),
                "error": unstaged.get("error", "") or staged_diff.get("error", ""),
            }
        await self.send(ws, Message(
            type=MessageType.GIT_DIFF_RESULT, payload=result))

    # -- Stage / Unstage (write) --

    async def handle_git_stage(self, client_id, ws, msg):
        """Stage files (or all changes) for commit.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``paths``, ``all``, and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitStagePayload)
        except PayloadValidationError as e:
            logger.warning(f" git.stage payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        manager, git = await self._require_repo(ws, payload.repo)
        if not manager:
            return

        async def _do_stage():
            if payload.all:
                return await git.stage_all()
            return await git.stage(payload.paths)

        op = Op.StageAll if payload.all else Op.Stage
        result = await manager.run(op, run_operation=_do_stage)

        await self.send(ws, Message(
            type=MessageType.GIT_STAGE_RESULT, payload=result))

    async def handle_git_unstage(self, client_id, ws, msg):
        """Unstage files (or all staged changes).

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``paths``, ``all``, and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitUnstagePayload)
        except PayloadValidationError as e:
            logger.warning(f" git.unstage payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        manager, git = await self._require_repo(ws, payload.repo)
        if not manager:
            return

        async def _do_unstage():
            if payload.all:
                return await git.unstage_all()
            return await git.unstage(payload.paths)

        op = Op.UnstageAll if payload.all else Op.Unstage
        result = await manager.run(op, run_operation=_do_unstage)

        await self.send(ws, Message(
            type=MessageType.GIT_UNSTAGE_RESULT, payload=result))

    # -- Commit (write) --

    async def handle_git_commit(self, client_id, ws, msg):
        """Create a Git commit with the given message.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``message`` and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitCommitPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.commit payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        manager, git = await self._require_repo(ws, payload.repo)
        if not manager:
            return

        logger.info(f": repo={Path(payload.repo).name}, message={payload.message[:50]}")

        def _optimistic():
            current = manager.status
            if current:
                return {"status": {**current, "staged": []}}
            return None

        result = await manager.run(
            Op.Commit,
            run_operation=lambda: git.commit(payload.message, no_verify=payload.no_verify),
            get_optimistic=_optimistic,
        )

        response = {**(result or {}), "repo": payload.repo}
        logger.debug(f"git.commit : hook_failed={response.get('hook_failed')}, success={response.get('success')}")
        await self.send(ws, Message(
            type=MessageType.GIT_COMMIT_RESULT,
            payload=response))

    # -- Push / Pull (write) --

    async def handle_git_push(self, client_id, ws, msg):
        """Push commits to the remote.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``repo``.
        """
        payload = msg.payload or {}
        repo_path = payload.get("repo", "")
        manager, git = await self._require_repo(ws, repo_path)
        if not manager:
            return

        logger.info(f": repo={Path(repo_path).name}")
        result = await manager.run(Op.Push, run_operation=git.push)

        if result.get("error"):
            logger.error(f"git.push : {result['error']}")
        await self.send(ws, Message(
            type=MessageType.GIT_PUSH_RESULT,
            payload={**(result or {}), "repo": repo_path}))

    async def handle_git_pull(self, client_id, ws, msg):
        """Pull changes from the remote.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``repo``.
        """
        payload = msg.payload or {}
        repo_path = payload.get("repo", "")
        manager, git = await self._require_repo(ws, repo_path)
        if not manager:
            return

        logger.info(f": repo={Path(repo_path).name}")
        result = await manager.run(Op.Pull, run_operation=git.pull)

        if result.get("error"):
            logger.error(f"git.pull : {result['error']}")
        await self.send(ws, Message(
            type=MessageType.GIT_PULL_RESULT,
            payload={**(result or {}), "repo": repo_path}))

    # -- Branches / Checkout (read/write) --

    async def handle_git_branches(self, client_id, ws, msg):
        """List all branches in a repository.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``repo`` field.
        """
        payload = msg.payload or {}
        repo_path = payload.get("repo", "")
        manager, git = await self._require_repo(ws, repo_path)
        if not manager:
            return

        if manager.branches is not None:
            await self.send(ws, Message(
                type=MessageType.GIT_BRANCHES_RESULT,
                payload={**manager.branches, "repo_path": repo_path}))
        else:
            result = await git.branches()
            await self.send(ws, Message(
                type=MessageType.GIT_BRANCHES_RESULT,
                payload={**result, "repo_path": repo_path}))

    async def handle_git_checkout(self, client_id, ws, msg):
        """Check out a branch.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``branch`` and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitCheckoutPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.checkout payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        repo_path = getattr(payload, 'repo', '') or ''
        manager, git = await self._require_repo(ws, repo_path)
        if not manager:
            return

        logger.info(f": repo={Path(repo_path).name}, branch={payload.branch}")
        result = await manager.run(
            Op.Checkout,
            run_operation=lambda: git.checkout(payload.branch),
        )

        await self.send(ws, Message(
            type=MessageType.GIT_CHECKOUT_RESULT,
            payload={**(result or {}), "repo": repo_path}))

    # -- Log (read) --

    async def handle_git_log(self, client_id, ws, msg):
        """Return the commit log for a repository.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``count`` and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitLogPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.log payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        repo_path = getattr(payload, 'repo', '') or ''
        manager, git = await self._require_repo(ws, repo_path)
        if not manager:
            return

        if manager.log_entries is not None:
            await self.send(ws, Message(
                type=MessageType.GIT_LOG_RESULT,
                payload={**manager.log_entries, "repo_path": repo_path}))
        else:
            result = await git.log(payload.count)
            await self.send(ws, Message(
                type=MessageType.GIT_LOG_RESULT,
                payload={**result, "repo_path": repo_path}))

    async def handle_git_log_authors(self, client_id, ws, msg):
        """Return the list of unique commit authors.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``repo`` field.
        """
        payload = msg.payload or {}
        repo_path = payload.get("repo", "")
        _, git = await self._require_repo(ws, repo_path)
        if not git:
            return

        authors = await git.log_authors()
        await self.send(ws, Message.from_typed(
            type=MessageType.GIT_LOG_AUTHORS_RESULT,
            payload=GitLogAuthorsResultPayload(authors=authors),
        ))

    async def handle_git_log_search(self, client_id, ws, msg):
        """Unified git log query -search + filter + pagination.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with search/filter params and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitLogSearchPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.log.search payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        repo_path = getattr(payload, 'repo', '') or ''
        _, git = self._get_repo_manager(repo_path)
        if not git:
            await self.send_error(ws, t("backend.gitNoRepoSpecified"))
            return

        logger.debug(f"git.log.search: repo={Path(repo_path).name}, query={payload.query!r}")
        result = await git.log(
            count=payload.count, skip=payload.skip, branch=payload.branch,
            author=payload.author, since=payload.since, until=payload.until,
            grep=payload.query,
        )
        await self.send(ws, Message(
            type=MessageType.GIT_LOG_SEARCH_RESULT,
            payload={**result, "repo_path": repo_path}))

    # -- Show / Diff commit (read) --

    async def handle_git_show(self, client_id, ws, msg):
        """Return commit details.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``hash`` and optional ``repo``.
        """
        try:
            payload = msg.typed_payload(GitShowPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.show payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        repo_path = getattr(payload, 'repo', '') or ''
        _, git = self._get_repo_manager(repo_path)
        if not git:
            await self.send_error(ws, t("backend.gitNoRepoSpecified"))
            return

        logger.debug(f"git.show: hash={payload.hash[:12]}")
        result = await git.show_commit(payload.hash)
        await self.send(ws, Message(
            type=MessageType.GIT_SHOW_RESULT, payload=result))

    async def handle_git_diff_commit(self, client_id, ws, msg):
        """Return old/new file content for a specific commit file.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``hash``, ``path``, and optional ``repo``.
        """
        try:
            payload = msg.typed_payload(GitDiffCommitPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.diff.commit payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        repo_path = getattr(payload, 'repo', '') or ''
        _, git = self._get_repo_manager(repo_path)
        if not git:
            await self.send_error(ws, t("backend.gitNoRepoSpecified"))
            return

        logger.debug(f"git.diff.commit: hash={payload.hash[:12]}, path={payload.path}")
        result = await git.diff_commit_file(payload.hash, payload.path)
        await self.send(ws, Message(
            type=MessageType.GIT_DIFF_COMMIT_RESULT, payload=result))

    # -- Discard (write) --

    async def handle_git_discard(self, client_id, ws, msg):
        """Discard changes to a single file.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path`` and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitDiscardPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.discard payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        repo_path = getattr(payload, 'repo', '') or ''
        manager, git = await self._require_repo(ws, repo_path)
        if not manager:
            return

        result = await manager.run(
            Op.Discard,
            run_operation=lambda: git.discard_file(payload.path),
        )

        await self.send(ws, Message(
            type=MessageType.GIT_DISCARD_RESULT, payload=result))

    # -- Repos discovery (read) --

    async def handle_git_repos(self, client_id, ws, msg):
        """Discover all Git repositories under the working directory.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``max_depth``.
        """
        try:
            payload = msg.typed_payload(GitReposPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.repos payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        logger.debug(f"git.repos: , max_depth={payload.max_depth}")
        # Use the discovery-only git service (root cwd)
        discovery_git = self.server.git_service
        repos = await discovery_git.discover_repos(
            root_dir=self.config.work_dir, max_depth=payload.max_depth)
        # No is_current marking - multi-repo has no "active" concept
        for repo in repos:
            repo["is_current"] = False
        logger.info(f" {len(repos)} ")
        await self.send(ws, Message.from_typed(
            type=MessageType.GIT_REPOS_RESULT,
            payload=GitReposResultPayload(repos=repos),
        ))

    # -- Shell exec (write) --

    async def handle_git_exec(self, client_id, ws, msg):
        """Execute an arbitrary Git command in a specific repository.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``command``, ``confirmed``, and ``repo``.
        """
        try:
            payload = msg.typed_payload(GitExecPayload)
        except PayloadValidationError as e:
            logger.warning(f" git.exec payload : client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        repo_path = getattr(payload, 'repo', '') or ''
        manager, git = await self._require_repo(ws, repo_path)
        if not manager:
            return

        logger.debug(f"git.exec: repo={Path(repo_path).name}, command={payload.command}")

        async def _do_exec():
            result = await git.execute_command(payload.command)
            if result.get("dangerous") and payload.confirmed:
                cmd = result["command"]
                if cmd.startswith("git "):
                    cmd = cmd[4:]
                parts = cmd.split()
                out, err, code = await git._run(
                    *parts, timeout=self.config.git.command_timeout
                )
                return {
                    "success": code == 0, "stdout": out, "stderr": err,
                    "command": result["command"], "blocked": False,
                    "reason": "", "dangerous": False,
                }
            return result

        result = await manager.run(Op.GitCommand, run_operation=_do_exec)

        await self.send(ws, Message(
            type=MessageType.GIT_EXEC_RESULT,
            payload={**(result or {}), "repo": repo_path}))

    # -- Merge Conflict Resolution --

    async def handle_git_conflicts(self, client_id, ws, msg):
        """Return parsed conflict blocks for a single file.

        Reads the file and parses conflict markers (<<<<<<< / ======= / >>>>>>>)
        into structured blocks with current/incoming content.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``repo`` and ``path``.
        """
        try:
            payload = msg.typed_payload(GitConflictsPayload)
        except PayloadValidationError as e:
            logger.warning(f"git.conflicts payload 无效: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        _, git = await self._require_repo(ws, payload.repo)
        if not git:
            return

        if not payload.path:
            await self.send_error(ws, "Missing file path")
            return

        logger.debug(f"git.conflicts: repo={Path(payload.repo).name}, path={payload.path}")
        result = await git.get_conflicts(payload.path)

        await self.send(ws, Message(
            type=MessageType.GIT_CONFLICTS_RESULT,
            payload={**result, "repo": payload.repo}))

    async def handle_git_conflict_resolve(self, client_id, ws, msg):
        """Resolve a single conflict block by immediately rewriting the file.

        Mirrors VS Code's immediate applyEdit() behavior: after resolution,
        the file is modified on disk and the updated conflict list (with
        recalculated IDs/line numbers) is returned.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``repo``, ``path``, ``conflict_id``, ``resolution``.
        """
        try:
            payload = msg.typed_payload(GitConflictResolvePayload)
        except PayloadValidationError as e:
            logger.warning(f"git.conflict.resolve payload 无效: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        manager, git = await self._require_repo(ws, payload.repo)
        if not manager:
            return

        if not payload.path:
            await self.send_error(ws, "Missing file path")
            return

        if payload.resolution not in ("current", "incoming", "both"):
            await self.send_error(ws, f"Invalid resolution: {payload.resolution}")
            return

        logger.info(
            f"git.conflict.resolve: repo={Path(payload.repo).name}, "
            f"path={payload.path}, id={payload.conflict_id}, "
            f"resolution={payload.resolution}"
        )

        result = await manager.run(
            Op.ConflictResolve,
            run_operation=lambda: git.resolve_conflict(
                payload.path, payload.conflict_id, payload.resolution
            ),
        )

        await self.send(ws, Message(
            type=MessageType.GIT_CONFLICT_RESOLVE_RESULT,
            payload={**(result or {}), "repo": payload.repo, "path": payload.path}))

    async def handle_git_conflict_resolve_all(self, client_id, ws, msg):
        """Resolve all conflicts in a file with the same strategy.

        Mirrors VS Code's acceptAll command — all conflicts are resolved
        in a single pass from bottom to top.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``repo``, ``path``, ``resolution``.
        """
        try:
            payload = msg.typed_payload(GitConflictResolveAllPayload)
        except PayloadValidationError as e:
            logger.warning(f"git.conflict.resolve.all payload 无效: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        manager, git = await self._require_repo(ws, payload.repo)
        if not manager:
            return

        if not payload.path:
            await self.send_error(ws, "Missing file path")
            return

        if payload.resolution not in ("current", "incoming", "both"):
            await self.send_error(ws, f"Invalid resolution: {payload.resolution}")
            return

        logger.info(
            f"git.conflict.resolve.all: repo={Path(payload.repo).name}, "
            f"path={payload.path}, resolution={payload.resolution}"
        )

        result = await manager.run(
            Op.ConflictResolve,
            run_operation=lambda: git.resolve_all_conflicts(
                payload.path, payload.resolution
            ),
        )

        await self.send(ws, Message(
            type=MessageType.GIT_CONFLICT_RESOLVE_ALL_RESULT,
            payload={**(result or {}), "repo": payload.repo, "path": payload.path}))

    async def handle_git_merge_abort(self, client_id, ws, msg):
        """Abort the current merge operation (git merge --abort).

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``repo``.
        """
        try:
            payload = msg.typed_payload(GitMergeAbortPayload)
        except PayloadValidationError as e:
            logger.warning(f"git.merge.abort payload 无效: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        manager, git = await self._require_repo(ws, payload.repo)
        if not manager:
            return

        logger.info(f"git.merge.abort: repo={Path(payload.repo).name}")

        result = await manager.run(
            Op.MergeAbort,
            run_operation=git.merge_abort,
        )

        await self.send(ws, Message(
            type=MessageType.GIT_MERGE_ABORT_RESULT,
            payload={**(result or {}), "repo": payload.repo}))
