/// git_operations.dart — All git-related send operations.
///
/// Depends on [MessageSender] interface only. Includes the git status
/// throttle logic (moved from WebSocketService) to prevent flooding
/// the Agent with redundant git commands.
library;

import '../../models/protocol.dart';
import '../../models/payloads/git_payloads.g.dart';
import '../ws_message_sender.dart';

/// Domain operations for git interactions.
///
/// Stateless sender — constructs and sends messages but does not
/// handle responses. Git results arrive via message handlers and
/// are forwarded on messageStream for GitStateProvider.
class GitOperations {
  final MessageSender _sender;

  GitOperations(this._sender);

  // ── Git status throttle ──
  // Multiple screens (files, git) may call requestGitStatus simultaneously.
  // Throttle to at most once per 2 seconds to avoid flooding the Agent
  // with redundant git commands (each takes ~650ms).
  DateTime? _lastGitStatusRequest;

  /// Request git status with global throttle (max once per 2s).
  void requestGitStatus() {
    final now = DateTime.now();
    if (_lastGitStatusRequest != null &&
        now.difference(_lastGitStatusRequest!).inMilliseconds < 2000) {
      return; // Throttled — skip duplicate request
    }
    _lastGitStatusRequest = now;
    _sender.send(WsMessage(
        type: MessageType.gitStatus,
        payload: const GitStatusPayload().toJson()));
  }

  /// Request git diff (used for #Git Diff context reference).
  void requestGitDiff() => _sender.send(WsMessage(
      type: MessageType.gitDiff,
      payload: const GitDiffPayload().toJson()));

  /// Stage files by [paths].
  void gitStage(List<String> paths) => _sender.send(WsMessage(
      type: MessageType.gitStage,
      payload: GitStagePayload(paths: paths).toJson()));

  /// Stage all changed files.
  void gitStageAll() => _sender.send(WsMessage(
      type: MessageType.gitStage,
      payload: const GitStagePayload(all: true).toJson()));

  /// Unstage files by [paths].
  void gitUnstage(List<String> paths) => _sender.send(WsMessage(
      type: MessageType.gitUnstage,
      payload: GitUnstagePayload(paths: paths).toJson()));

  /// Unstage all staged files.
  void gitUnstageAll() => _sender.send(WsMessage(
      type: MessageType.gitUnstage,
      payload: const GitUnstagePayload(all: true).toJson()));

  /// Commit staged changes with [message].
  void gitCommit(String message) => _sender.send(WsMessage(
      type: MessageType.gitCommit,
      payload: GitCommitPayload(message: message).toJson()));

  /// Push to remote.
  void gitPush() => _sender.send(WsMessage(
      type: MessageType.gitPush,
      payload: const GitPushPayload().toJson()));

  /// Pull from remote.
  void gitPull() => _sender.send(WsMessage(
      type: MessageType.gitPull,
      payload: const GitPullPayload().toJson()));

  /// List all branches.
  void gitBranches() => _sender.send(WsMessage(
      type: MessageType.gitBranches,
      payload: const GitBranchesPayload().toJson()));

  /// Checkout a [branch].
  void gitCheckout(String branch) => _sender.send(WsMessage(
      type: MessageType.gitCheckout,
      payload: GitCheckoutPayload(branch: branch).toJson()));

  /// Fetch git log (last [count] commits).
  void gitLog({int count = 50}) => _sender.send(WsMessage(
      type: MessageType.gitLog,
      payload: GitLogPayload(count: count).toJson()));

  /// Unified git log query — search + filter + pagination in one call.
  ///
  /// All parameters are optional. Combines text search, branch/author
  /// filters, date range, and pagination into a single request.
  void gitLogSearch({
    String query = '',
    String branch = '',
    String author = '',
    String since = '',
    String until = '',
    int skip = 0,
    int count = 50,
  }) =>
      _sender.send(WsMessage(
          type: MessageType.gitLogSearch,
          payload: GitLogSearchPayload(
            query: query,
            branch: branch,
            author: author,
            since: since,
            until: until,
            skip: skip,
            count: count,
          ).toJson()));

  /// Request the list of unique commit authors for filter UI.
  void gitLogAuthors() => _sender.send(WsMessage(
      type: MessageType.gitLogAuthors,
      payload: const GitLogAuthorsPayload().toJson()));

  /// Fetch commit details (metadata + changed files).
  void gitShow(String hash) => _sender.send(WsMessage(
      type: MessageType.gitShow,
      payload: GitShowPayload(hash: hash).toJson()));

  /// Fetch old/new file content for a specific commit and file path.
  void gitDiffCommit({required String hash, required String path}) =>
      _sender.send(WsMessage(
          type: MessageType.gitDiffCommit,
          payload:
              GitDiffCommitPayload(hash: hash, path: path).toJson()));

  /// Get diff for a specific file [path], optionally [staged].
  void gitDiffFile(String path, {bool staged = false}) =>
      _sender.send(WsMessage(
          type: MessageType.gitDiff,
          payload: GitDiffPayload(path: path, staged: staged).toJson()));

  /// Discard changes for a file at [path].
  void gitDiscard(String path) => _sender.send(WsMessage(
      type: MessageType.gitDiscard,
      payload: GitDiscardPayload(path: path).toJson()));

  /// Discover all git repos under the working directory.
  void requestGitRepos({int maxDepth = 3}) => _sender.send(WsMessage(
      type: MessageType.gitRepos,
      payload: GitReposPayload(maxDepth: maxDepth).toJson()));

  /// Switch the active git repository.
  void switchGitRepo(String path) => _sender.send(WsMessage(
      type: MessageType.gitSwitchRepo,
      payload: GitSwitchRepoPayload(path: path).toJson()));

  /// Execute a git shell command (restricted to git operations only).
  void execGitCommand(String command, {bool confirmed = false}) =>
      _sender.send(WsMessage(
          type: MessageType.gitExec,
          payload: GitExecPayload(
              command: command, confirmed: confirmed).toJson()));
}
