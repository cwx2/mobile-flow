/// repo_state.dart — Data model for a single repository's git state.
///
/// Used by GitStateProvider to hold per-repo state in multi-repo mode.
/// Immutable value object — replaced on each state update.
library;

/// Complete git state for a single repository.
///
/// Contains the same data as the old global GitStateProvider fields,
/// but scoped to one repository. Multiple instances coexist in
/// GitStateProvider._repos for the aggregated multi-repo view.
class RepoState {
  final String path;
  final String name;
  final String branch;
  final int ahead;
  final int behind;
  final List<Map<String, dynamic>> staged;
  final List<Map<String, dynamic>> unstaged;
  final List<Map<String, dynamic>> untracked;
  final String error;

  const RepoState({
    required this.path,
    required this.name,
    this.branch = '',
    this.ahead = 0,
    this.behind = 0,
    this.staged = const [],
    this.unstaged = const [],
    this.untracked = const [],
    this.error = '',
  });

  /// Total number of changed files in this repository.
  int get totalChanges => staged.length + unstaged.length + untracked.length;

  /// Whether this repository has any uncommitted changes.
  bool get hasChanges => totalChanges > 0;

  /// Whether this repository has staged files ready to commit.
  bool get hasStagedChanges => staged.isNotEmpty;

  /// Create from a status payload dict (from Agent state.push or git.status.all.result).
  factory RepoState.fromJson(Map<String, dynamic> json) {
    return RepoState(
      path: json['path'] as String? ?? json['repo_path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      branch: json['branch'] as String? ?? '',
      ahead: json['ahead'] as int? ?? 0,
      behind: json['behind'] as int? ?? 0,
      staged: _parseFileList(json['staged']),
      unstaged: _parseFileList(json['unstaged']),
      untracked: _parseFileList(json['untracked']),
      error: json['error'] as String? ?? '',
    );
  }

  static List<Map<String, dynamic>> _parseFileList(dynamic data) {
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }
}
