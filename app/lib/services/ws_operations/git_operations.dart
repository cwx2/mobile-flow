/// git_operations.dart — All git-related send operations (multi-repo).
///
/// Every write operation requires an explicit [repo] path parameter.
/// No global "active repo" state — each message is self-describing.
library;

import '../../models/protocol.dart';
import '../../models/payloads/git_payloads.g.dart';
import '../ws_message_sender.dart';

/// Domain operations for git interactions (multi-repo architecture).
///
/// Stateless sender — constructs and sends messages. All write operations
/// require a [repo] parameter to identify the target repository.
class GitOperations {
  final MessageSender _sender;

  GitOperations(this._sender);

  // ── Status ──

  /// Request aggregated status of all repositories (primary endpoint).
  void requestGitStatusAll() => _sender.send(WsMessage(
      type: MessageType.gitStatusAll,
      payload: const <String, dynamic>{}));

  /// Request status of a single repo (backward compat).
  void requestGitStatus({String repo = ''}) => _sender.send(WsMessage(
      type: MessageType.gitStatus,
      payload: GitStatusPayload(repo: repo).toJson()));

  // ── Diff ──

  /// Request git diff (whole repo or single file).
  void requestGitDiff({String repo = ''}) => _sender.send(WsMessage(
      type: MessageType.gitDiff,
      payload: GitDiffPayload(repo: repo).toJson()));

  /// Get diff for a specific file [path], optionally [staged].
  void gitDiffFile(String path, {required String repo, bool staged = false}) =>
      _sender.send(WsMessage(
          type: MessageType.gitDiff,
          payload: GitDiffPayload(path: path, staged: staged, repo: repo).toJson()));

  // ── Stage / Unstage ──

  /// Stage files by [paths] in a specific [repo].
  void gitStage(List<String> paths, {required String repo}) =>
      _sender.send(WsMessage(
          type: MessageType.gitStage,
          payload: GitStagePayload(paths: paths, repo: repo).toJson()));

  /// Stage all changed files in a specific [repo].
  void gitStageAll({required String repo}) => _sender.send(WsMessage(
      type: MessageType.gitStage,
      payload: GitStagePayload(all: true, repo: repo).toJson()));

  /// Unstage files by [paths] in a specific [repo].
  void gitUnstage(List<String> paths, {required String repo}) =>
      _sender.send(WsMessage(
          type: MessageType.gitUnstage,
          payload: GitUnstagePayload(paths: paths, repo: repo).toJson()));

  /// Unstage all staged files in a specific [repo].
  void gitUnstageAll({required String repo}) => _sender.send(WsMessage(
      type: MessageType.gitUnstage,
      payload: GitUnstagePayload(all: true, repo: repo).toJson()));

  // ── Commit / Push / Pull ──

  /// Commit staged changes with [message] in a specific [repo].
  void gitCommit(String message, {required String repo, bool noVerify = false}) =>
      _sender.send(WsMessage(
          type: MessageType.gitCommit,
          payload: GitCommitPayload(message: message, repo: repo, noVerify: noVerify).toJson()));

  /// Push to remote for a specific [repo].
  void gitPush({required String repo}) => _sender.send(WsMessage(
      type: MessageType.gitPush,
      payload: GitPushPayload(repo: repo).toJson()));

  /// Pull from remote for a specific [repo].
  void gitPull({required String repo}) => _sender.send(WsMessage(
      type: MessageType.gitPull,
      payload: GitPullPayload(repo: repo).toJson()));

  // ── Branches / Checkout ──

  /// List all branches for a specific [repo].
  void gitBranches({String repo = ''}) => _sender.send(WsMessage(
      type: MessageType.gitBranches,
      payload: GitBranchesPayload(repo: repo).toJson()));

  /// Checkout a [branch] in a specific [repo].
  void gitCheckout(String branch, {required String repo}) =>
      _sender.send(WsMessage(
          type: MessageType.gitCheckout,
          payload: GitCheckoutPayload(branch: branch, repo: repo).toJson()));

  // ── Log ──

  /// Fetch git log for a specific [repo].
  void gitLog({String repo = '', int count = 50}) =>
      _sender.send(WsMessage(
          type: MessageType.gitLog,
          payload: GitLogPayload(count: count, repo: repo).toJson()));

  /// Unified git log query — search + filter + pagination.
  void gitLogSearch({
    String repo = '',
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
            repo: repo,
          ).toJson()));

  /// Request the list of unique commit authors.
  void gitLogAuthors({String repo = ''}) => _sender.send(WsMessage(
      type: MessageType.gitLogAuthors,
      payload: GitLogAuthorsPayload(repo: repo).toJson()));

  /// Fetch commit details.
  void gitShow(String hash, {String repo = ''}) => _sender.send(WsMessage(
      type: MessageType.gitShow,
      payload: GitShowPayload(hash: hash, repo: repo).toJson()));

  /// Fetch old/new file content for a specific commit file.
  void gitDiffCommit({required String hash, required String path, String repo = ''}) =>
      _sender.send(WsMessage(
          type: MessageType.gitDiffCommit,
          payload: GitDiffCommitPayload(hash: hash, path: path, repo: repo).toJson()));

  // ── Discard ──

  /// Discard changes for a file at [path] in a specific [repo].
  void gitDiscard(String path, {required String repo}) =>
      _sender.send(WsMessage(
          type: MessageType.gitDiscard,
          payload: GitDiscardPayload(path: path, repo: repo).toJson()));

  // ── Discovery ──

  /// Discover all git repos under the working directory.
  void requestGitRepos({int maxDepth = 3}) => _sender.send(WsMessage(
      type: MessageType.gitRepos,
      payload: GitReposPayload(maxDepth: maxDepth).toJson()));

  // ── Shell exec ──

  /// Execute a git shell command in a specific [repo].
  void execGitCommand(String command, {String repo = '', bool confirmed = false}) =>
      _sender.send(WsMessage(
          type: MessageType.gitExec,
          payload: GitExecPayload(
              command: command, confirmed: confirmed, repo: repo).toJson()));
}
