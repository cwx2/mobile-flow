// RepoState model tests.
//
// Covers:
//   - fromJson parsing all fields
//   - totalChanges / hasChanges / hasStagedChanges computed properties
//   - Missing fields default to empty/zero
//   - repo_path fallback (path vs repo_path key)

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/repo_state.dart';

void main() {
  group('RepoState.fromJson', () {
    test('parses all fields correctly', () {
      final state = RepoState.fromJson({
        'path': '/project/frontend',
        'name': 'frontend',
        'branch': 'main',
        'ahead': 2,
        'behind': 1,
        'staged': [
          {'path': 'src/app.ts', 'status': 'M'}
        ],
        'unstaged': [
          {'path': 'README.md', 'status': 'M'}
        ],
        'untracked': [
          {'path': 'temp.log', 'status': '?'}
        ],
        'error': '',
      });

      expect(state.path, '/project/frontend');
      expect(state.name, 'frontend');
      expect(state.branch, 'main');
      expect(state.ahead, 2);
      expect(state.behind, 1);
      expect(state.staged.length, 1);
      expect(state.unstaged.length, 1);
      expect(state.untracked.length, 1);
      expect(state.error, '');
    });

    test('missing fields default to empty', () {
      final state = RepoState.fromJson({});

      expect(state.path, '');
      expect(state.name, '');
      expect(state.branch, '');
      expect(state.ahead, 0);
      expect(state.behind, 0);
      expect(state.staged, isEmpty);
      expect(state.unstaged, isEmpty);
      expect(state.untracked, isEmpty);
    });

    test('repo_path fallback for path field', () {
      final state = RepoState.fromJson({
        'repo_path': '/project/backend',
        'name': 'backend',
      });

      expect(state.path, '/project/backend');
    });

    test('path takes priority over repo_path', () {
      final state = RepoState.fromJson({
        'path': '/correct',
        'repo_path': '/fallback',
        'name': 'test',
      });

      expect(state.path, '/correct');
    });
  });

  group('RepoState computed properties', () {
    test('totalChanges sums all categories', () {
      final state = RepoState(
        path: '/repo',
        name: 'repo',
        staged: [
          {'path': 'a', 'status': 'M'},
          {'path': 'b', 'status': 'A'},
        ],
        unstaged: [
          {'path': 'c', 'status': 'M'},
        ],
        untracked: [
          {'path': 'd', 'status': '?'},
          {'path': 'e', 'status': '?'},
        ],
      );

      expect(state.totalChanges, 5);
    });

    test('hasChanges true when any category non-empty', () {
      final clean = RepoState(path: '/clean', name: 'clean');
      final dirty = RepoState(
        path: '/dirty',
        name: 'dirty',
        untracked: [
          {'path': 'x', 'status': '?'}
        ],
      );

      expect(clean.hasChanges, false);
      expect(dirty.hasChanges, true);
    });

    test('hasStagedChanges only checks staged', () {
      final noStaged = RepoState(
        path: '/r',
        name: 'r',
        unstaged: [
          {'path': 'a', 'status': 'M'}
        ],
      );
      final hasStaged = RepoState(
        path: '/r',
        name: 'r',
        staged: [
          {'path': 'a', 'status': 'M'}
        ],
      );

      expect(noStaged.hasStagedChanges, false);
      expect(hasStaged.hasStagedChanges, true);
    });
  });
}
