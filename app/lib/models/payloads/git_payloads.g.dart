// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/git.py

/// Payload for ``git.status`` — request repo status.
class GitStatusPayload {
  const GitStatusPayload();

  factory GitStatusPayload.fromJson(Map<String, dynamic> json) {
    return const GitStatusPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}

/// Payload for ``git.status.result`` — repository status.
class GitStatusResultPayload {
  final String branch;
  final List<Map<String, dynamic>> staged;
  final List<Map<String, dynamic>> unstaged;
  final List<String> untracked;
  final int ahead;
  final int behind;
  final String? error;

  const GitStatusResultPayload({
    this.branch = '',
    this.staged = const [],
    this.unstaged = const [],
    this.untracked = const [],
    this.ahead = 0,
    this.behind = 0,
    this.error = null,
  });

  factory GitStatusResultPayload.fromJson(Map<String, dynamic> json) {
    return GitStatusResultPayload(
      branch: json['branch'] as String? ?? '',
      staged: (json['staged'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      unstaged: (json['unstaged'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      untracked: (json['untracked'] as List? ?? []).map((e) => e as String).toList(),
      ahead: json['ahead'] as int? ?? 0,
      behind: json['behind'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'branch': branch,
        'staged': staged,
        'unstaged': unstaged,
        'untracked': untracked,
        'ahead': ahead,
        'behind': behind,
        'error': error,
      };
}

/// Payload for ``git.diff`` — request file diff.
class GitDiffPayload {
  final String path;
  final bool staged;

  const GitDiffPayload({
    this.path = '',
    this.staged = false,
  });

  factory GitDiffPayload.fromJson(Map<String, dynamic> json) {
    return GitDiffPayload(
      path: json['path'] as String? ?? '',
      staged: json['staged'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'staged': staged,
      };
}

/// Payload for ``git.diff.result`` — diff content.
class GitDiffResultPayload {
  final String diff;
  final String staged;
  final String? oldContent;
  final String? newContent;
  final String? language;
  final String? error;

  const GitDiffResultPayload({
    this.diff = '',
    this.staged = '',
    this.oldContent = null,
    this.newContent = null,
    this.language = null,
    this.error = null,
  });

  factory GitDiffResultPayload.fromJson(Map<String, dynamic> json) {
    return GitDiffResultPayload(
      diff: json['diff'] as String? ?? '',
      staged: json['staged'] as String? ?? '',
      oldContent: json['old_content'] as String?,
      newContent: json['new_content'] as String?,
      language: json['language'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'diff': diff,
        'staged': staged,
        'old_content': oldContent,
        'new_content': newContent,
        'language': language,
        'error': error,
      };
}

/// Payload for ``git.stage`` — stage files for commit.
class GitStagePayload {
  final List<String> paths;
  final bool all;

  const GitStagePayload({
    this.paths = const [],
    this.all = false,
  });

  factory GitStagePayload.fromJson(Map<String, dynamic> json) {
    return GitStagePayload(
      paths: (json['paths'] as List? ?? []).map((e) => e as String).toList(),
      all: json['all'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'paths': paths,
        'all': all,
      };
}

/// Payload for ``git.stage.result`` — stage operation result.
class GitStageResultPayload {
  final bool success;
  final String? error;

  const GitStageResultPayload({
    this.success = false,
    this.error = null,
  });

  factory GitStageResultPayload.fromJson(Map<String, dynamic> json) {
    return GitStageResultPayload(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'error': error,
      };
}

/// Payload for ``git.unstage`` — unstage files.
class GitUnstagePayload {
  final List<String> paths;
  final bool all;

  const GitUnstagePayload({
    this.paths = const [],
    this.all = false,
  });

  factory GitUnstagePayload.fromJson(Map<String, dynamic> json) {
    return GitUnstagePayload(
      paths: (json['paths'] as List? ?? []).map((e) => e as String).toList(),
      all: json['all'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'paths': paths,
        'all': all,
      };
}

/// Payload for ``git.unstage.result`` — unstage operation result.
class GitUnstageResultPayload {
  final bool success;
  final String? error;

  const GitUnstageResultPayload({
    this.success = false,
    this.error = null,
  });

  factory GitUnstageResultPayload.fromJson(Map<String, dynamic> json) {
    return GitUnstageResultPayload(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'error': error,
      };
}

/// Payload for ``git.commit`` — create a commit.
class GitCommitPayload {
  final String message;

  const GitCommitPayload({
    this.message = '',
  });

  factory GitCommitPayload.fromJson(Map<String, dynamic> json) {
    return GitCommitPayload(
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'message': message,
      };
}

/// Payload for ``git.commit.result`` — commit operation result.
class GitCommitResultPayload {
  final bool success;
  final String? hash;
  final String? error;

  const GitCommitResultPayload({
    this.success = false,
    this.hash = null,
    this.error = null,
  });

  factory GitCommitResultPayload.fromJson(Map<String, dynamic> json) {
    return GitCommitResultPayload(
      success: json['success'] as bool? ?? false,
      hash: json['hash'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'hash': hash,
        'error': error,
      };
}

/// Payload for ``git.push`` — push commits to remote.
class GitPushPayload {
  const GitPushPayload();

  factory GitPushPayload.fromJson(Map<String, dynamic> json) {
    return const GitPushPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}

/// Payload for ``git.push.result`` — push operation result.
class GitPushResultPayload {
  final bool success;
  final String output;
  final bool upToDate;
  final String? error;

  const GitPushResultPayload({
    this.success = false,
    this.output = '',
    this.upToDate = false,
    this.error = null,
  });

  factory GitPushResultPayload.fromJson(Map<String, dynamic> json) {
    return GitPushResultPayload(
      success: json['success'] as bool? ?? false,
      output: json['output'] as String? ?? '',
      upToDate: json['up_to_date'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'output': output,
        'up_to_date': upToDate,
        'error': error,
      };
}

/// Payload for ``git.pull`` — pull changes from remote.
class GitPullPayload {
  const GitPullPayload();

  factory GitPullPayload.fromJson(Map<String, dynamic> json) {
    return const GitPullPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}

/// Payload for ``git.pull.result`` — pull operation result.
class GitPullResultPayload {
  final bool success;
  final String output;
  final bool upToDate;
  final String? error;

  const GitPullResultPayload({
    this.success = false,
    this.output = '',
    this.upToDate = false,
    this.error = null,
  });

  factory GitPullResultPayload.fromJson(Map<String, dynamic> json) {
    return GitPullResultPayload(
      success: json['success'] as bool? ?? false,
      output: json['output'] as String? ?? '',
      upToDate: json['up_to_date'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'output': output,
        'up_to_date': upToDate,
        'error': error,
      };
}

/// Payload for ``git.branches`` — list all branches.
class GitBranchesPayload {
  const GitBranchesPayload();

  factory GitBranchesPayload.fromJson(Map<String, dynamic> json) {
    return const GitBranchesPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}

/// Payload for ``git.branches.result`` — branch list.
class GitBranchesResultPayload {
  final List<Map<String, dynamic>> branches;
  final String current;
  final String? error;

  const GitBranchesResultPayload({
    this.branches = const [],
    this.current = '',
    this.error = null,
  });

  factory GitBranchesResultPayload.fromJson(Map<String, dynamic> json) {
    return GitBranchesResultPayload(
      branches: (json['branches'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      current: json['current'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'branches': branches,
        'current': current,
        'error': error,
      };
}

/// Payload for ``git.checkout`` — switch to a branch.
class GitCheckoutPayload {
  final String branch;

  const GitCheckoutPayload({
    this.branch = '',
  });

  factory GitCheckoutPayload.fromJson(Map<String, dynamic> json) {
    return GitCheckoutPayload(
      branch: json['branch'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'branch': branch,
      };
}

/// Payload for ``git.checkout.result`` — checkout operation result.
class GitCheckoutResultPayload {
  final bool success;
  final String? error;

  const GitCheckoutResultPayload({
    this.success = false,
    this.error = null,
  });

  factory GitCheckoutResultPayload.fromJson(Map<String, dynamic> json) {
    return GitCheckoutResultPayload(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'error': error,
      };
}

/// Payload for ``git.log`` — request commit log.
class GitLogPayload {
  final int count;

  const GitLogPayload({
    this.count = 50,
  });

  factory GitLogPayload.fromJson(Map<String, dynamic> json) {
    return GitLogPayload(
      count: json['count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'count': count,
      };
}

/// Payload for ``git.log.result`` — commit log.
class GitLogResultPayload {
  final List<Map<String, dynamic>> entries;
  final bool hasMore;
  final String? error;

  const GitLogResultPayload({
    this.entries = const [],
    this.hasMore = false,
    this.error = null,
  });

  factory GitLogResultPayload.fromJson(Map<String, dynamic> json) {
    return GitLogResultPayload(
      entries: (json['entries'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      hasMore: json['has_more'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'entries': entries,
        'has_more': hasMore,
        'error': error,
      };
}

/// Payload for ``git.log.search`` — unified log query with filters.
class GitLogSearchPayload {
  final String query;
  final String branch;
  final String author;
  final String since;
  final String until;
  final int skip;
  final int count;

  const GitLogSearchPayload({
    this.query = '',
    this.branch = '',
    this.author = '',
    this.since = '',
    this.until = '',
    this.skip = 0,
    this.count = 50,
  });

  factory GitLogSearchPayload.fromJson(Map<String, dynamic> json) {
    return GitLogSearchPayload(
      query: json['query'] as String? ?? '',
      branch: json['branch'] as String? ?? '',
      author: json['author'] as String? ?? '',
      since: json['since'] as String? ?? '',
      until: json['until'] as String? ?? '',
      skip: json['skip'] as int? ?? 0,
      count: json['count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'branch': branch,
        'author': author,
        'since': since,
        'until': until,
        'skip': skip,
        'count': count,
      };
}

/// Payload for ``git.log.search.result`` — log search results.
class GitLogSearchResultPayload {
  final List<Map<String, dynamic>> entries;
  final bool hasMore;
  final String query;
  final String? error;

  const GitLogSearchResultPayload({
    this.entries = const [],
    this.hasMore = false,
    this.query = '',
    this.error = null,
  });

  factory GitLogSearchResultPayload.fromJson(Map<String, dynamic> json) {
    return GitLogSearchResultPayload(
      entries: (json['entries'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      hasMore: json['has_more'] as bool? ?? false,
      query: json['query'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'entries': entries,
        'has_more': hasMore,
        'query': query,
        'error': error,
      };
}

/// Payload for ``git.log.authors`` — list unique commit authors.
class GitLogAuthorsPayload {
  const GitLogAuthorsPayload();

  factory GitLogAuthorsPayload.fromJson(Map<String, dynamic> json) {
    return const GitLogAuthorsPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}

/// Payload for ``git.log.authors.result`` — unique author list.
class GitLogAuthorsResultPayload {
  final List<String> authors;

  const GitLogAuthorsResultPayload({
    this.authors = const [],
  });

  factory GitLogAuthorsResultPayload.fromJson(Map<String, dynamic> json) {
    return GitLogAuthorsResultPayload(
      authors: (json['authors'] as List? ?? []).map((e) => e as String).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'authors': authors,
      };
}

/// Payload for ``git.show`` — show commit details.
class GitShowPayload {
  final String hash;

  const GitShowPayload({
    this.hash = '',
  });

  factory GitShowPayload.fromJson(Map<String, dynamic> json) {
    return GitShowPayload(
      hash: json['hash'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'hash': hash,
      };
}

/// Payload for ``git.show.result`` — commit details.
class GitShowResultPayload {
  final String hash;
  final String shortHash;
  final String author;
  final String date;
  final String message;
  final String fullMessage;
  final List<Map<String, dynamic>> files;
  final String? error;

  const GitShowResultPayload({
    this.hash = '',
    this.shortHash = '',
    this.author = '',
    this.date = '',
    this.message = '',
    this.fullMessage = '',
    this.files = const [],
    this.error = null,
  });

  factory GitShowResultPayload.fromJson(Map<String, dynamic> json) {
    return GitShowResultPayload(
      hash: json['hash'] as String? ?? '',
      shortHash: json['short_hash'] as String? ?? '',
      author: json['author'] as String? ?? '',
      date: json['date'] as String? ?? '',
      message: json['message'] as String? ?? '',
      fullMessage: json['full_message'] as String? ?? '',
      files: (json['files'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'short_hash': shortHash,
        'author': author,
        'date': date,
        'message': message,
        'full_message': fullMessage,
        'files': files,
        'error': error,
      };
}

/// Payload for ``git.diff.commit`` — diff a specific commit file.
class GitDiffCommitPayload {
  final String hash;
  final String path;

  const GitDiffCommitPayload({
    this.hash = '',
    this.path = '',
  });

  factory GitDiffCommitPayload.fromJson(Map<String, dynamic> json) {
    return GitDiffCommitPayload(
      hash: json['hash'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'path': path,
      };
}

/// Payload for ``git.diff.commit.result`` — commit file diff.
class GitDiffCommitResultPayload {
  final String oldContent;
  final String newContent;
  final String language;
  final String? error;

  const GitDiffCommitResultPayload({
    this.oldContent = '',
    this.newContent = '',
    this.language = '',
    this.error = null,
  });

  factory GitDiffCommitResultPayload.fromJson(Map<String, dynamic> json) {
    return GitDiffCommitResultPayload(
      oldContent: json['old_content'] as String? ?? '',
      newContent: json['new_content'] as String? ?? '',
      language: json['language'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'old_content': oldContent,
        'new_content': newContent,
        'language': language,
        'error': error,
      };
}

/// Payload for ``git.discard`` — discard changes to a file.
class GitDiscardPayload {
  final String path;

  const GitDiscardPayload({
    this.path = '',
  });

  factory GitDiscardPayload.fromJson(Map<String, dynamic> json) {
    return GitDiscardPayload(
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
      };
}

/// Payload for ``git.discard.result`` — discard operation result.
class GitDiscardResultPayload {
  final bool success;
  final String? error;

  const GitDiscardResultPayload({
    this.success = false,
    this.error = null,
  });

  factory GitDiscardResultPayload.fromJson(Map<String, dynamic> json) {
    return GitDiscardResultPayload(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'error': error,
      };
}

/// Payload for ``git.repos`` — discover git repositories.
class GitReposPayload {
  final int maxDepth;

  const GitReposPayload({
    this.maxDepth = 3,
  });

  factory GitReposPayload.fromJson(Map<String, dynamic> json) {
    return GitReposPayload(
      maxDepth: json['max_depth'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'max_depth': maxDepth,
      };
}

/// Payload for ``git.repos.result`` — discovered repository list.
class GitReposResultPayload {
  final List<Map<String, dynamic>> repos;

  const GitReposResultPayload({
    this.repos = const [],
  });

  factory GitReposResultPayload.fromJson(Map<String, dynamic> json) {
    return GitReposResultPayload(
      repos: (json['repos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'repos': repos,
      };
}

/// Payload for ``git.switch_repo`` — switch active repository.
class GitSwitchRepoPayload {
  final String path;

  const GitSwitchRepoPayload({
    this.path = '',
  });

  factory GitSwitchRepoPayload.fromJson(Map<String, dynamic> json) {
    return GitSwitchRepoPayload(
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
      };
}

/// Payload for ``git.exec`` — execute arbitrary git command.
class GitExecPayload {
  final String command;
  final bool confirmed;

  const GitExecPayload({
    this.command = '',
    this.confirmed = false,
  });

  factory GitExecPayload.fromJson(Map<String, dynamic> json) {
    return GitExecPayload(
      command: json['command'] as String? ?? '',
      confirmed: json['confirmed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'command': command,
        'confirmed': confirmed,
      };
}

/// Payload for ``git.exec.result`` — git command execution result.
class GitExecResultPayload {
  final bool success;
  final String output;
  final String stdout;
  final String stderr;
  final String command;
  final bool blocked;
  final String reason;
  final bool dangerous;
  final String? error;

  const GitExecResultPayload({
    this.success = false,
    this.output = '',
    this.stdout = '',
    this.stderr = '',
    this.command = '',
    this.blocked = false,
    this.reason = '',
    this.dangerous = false,
    this.error = null,
  });

  factory GitExecResultPayload.fromJson(Map<String, dynamic> json) {
    return GitExecResultPayload(
      success: json['success'] as bool? ?? false,
      output: json['output'] as String? ?? '',
      stdout: json['stdout'] as String? ?? '',
      stderr: json['stderr'] as String? ?? '',
      command: json['command'] as String? ?? '',
      blocked: json['blocked'] as bool? ?? false,
      reason: json['reason'] as String? ?? '',
      dangerous: json['dangerous'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'output': output,
        'stdout': stdout,
        'stderr': stderr,
        'command': command,
        'blocked': blocked,
        'reason': reason,
        'dangerous': dangerous,
        'error': error,
      };
}
