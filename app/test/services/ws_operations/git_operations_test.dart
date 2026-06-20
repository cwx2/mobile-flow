// GitOperations tests
//
// Covers: correct MessageType for each method, git status throttle,
// gitStage paths, gitLogSearch parameters, gitDiffFile staged flag.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/protocol.dart';
import 'package:mobileflow/services/ws_message_sender.dart';
import 'package:mobileflow/services/ws_operations/git_operations.dart';

/// Mock MessageSender that captures sent WsMessage objects.
class _MockSender implements MessageSender {
  final List<WsMessage> sent = [];

  @override
  String get defaultCli => 'test-cli';

  @override
  void send(WsMessage msg) => sent.add(msg);

  /// Get the last sent message, or null.
  WsMessage? get last => sent.isNotEmpty ? sent.last : null;

  /// Get all messages of a given type.
  List<WsMessage> ofType(String type) =>
      sent.where((m) => m.type == type).toList();
}

void main() {
  late _MockSender sender;
  late GitOperations git;

  const testRepo = '/path/to/repo';

  setUp(() {
    sender = _MockSender();
    git = GitOperations(sender);
  });

  group('GitOperations — 消息类型', () {
    test('requestGitStatus 发送 git.status', () {
      git.requestGitStatus();
      expect(sender.last?.type, MessageType.gitStatus);
    });

    test('requestGitDiff 发送 git.diff', () {
      git.requestGitDiff();
      expect(sender.last?.type, MessageType.gitDiff);
    });

    test('gitStage 发送 git.stage', () {
      git.gitStage(['a.py'], repo: testRepo);
      expect(sender.last?.type, MessageType.gitStage);
    });

    test('gitStageAll 发送 git.stage with all=true', () {
      git.gitStageAll(repo: testRepo);
      expect(sender.last?.type, MessageType.gitStage);
      expect(sender.last?.payload['all'], true);
    });

    test('gitUnstage 发送 git.unstage', () {
      git.gitUnstage(['b.py'], repo: testRepo);
      expect(sender.last?.type, MessageType.gitUnstage);
    });

    test('gitCommit 发送 git.commit', () {
      git.gitCommit('fix: typo', repo: testRepo);
      expect(sender.last?.type, MessageType.gitCommit);
      expect(sender.last?.payload['message'], 'fix: typo');
    });

    test('gitPush 发送 git.push', () {
      git.gitPush(repo: testRepo);
      expect(sender.last?.type, MessageType.gitPush);
    });

    test('gitPull 发送 git.pull', () {
      git.gitPull(repo: testRepo);
      expect(sender.last?.type, MessageType.gitPull);
    });

    test('gitBranches 发送 git.branches', () {
      git.gitBranches();
      expect(sender.last?.type, MessageType.gitBranches);
    });

    test('gitCheckout 发送 git.checkout', () {
      git.gitCheckout('main', repo: testRepo);
      expect(sender.last?.type, MessageType.gitCheckout);
      expect(sender.last?.payload['branch'], 'main');
    });

    test('gitLog 发送 git.log', () {
      git.gitLog(count: 20);
      expect(sender.last?.type, MessageType.gitLog);
      expect(sender.last?.payload['count'], 20);
    });

    test('gitShow 发送 git.show', () {
      git.gitShow('abc123');
      expect(sender.last?.type, MessageType.gitShow);
      expect(sender.last?.payload['hash'], 'abc123');
    });
  });

  group('GitOperations — git status 请求', () {
    test('多次调用都正常发送（节流已移至 GitStateProvider）', () {
      git.requestGitStatus();
      git.requestGitStatus();
      // Throttle logic now lives in GitStateProvider.requestInitialData(),
      // not in GitOperations. GitOperations is a pure message sender.
      expect(sender.ofType(MessageType.gitStatus).length, 2);
    });
  });

  group('GitOperations — payload 参数', () {
    test('gitStage 发送正确的 paths', () {
      git.gitStage(['src/main.py', 'README.md'], repo: testRepo);
      final payload = sender.last!.payload;
      expect(payload['paths'], ['src/main.py', 'README.md']);
    });

    test('gitLogSearch 发送所有参数', () {
      git.gitLogSearch(
        query: 'fix',
        branch: 'main',
        author: 'dev@test.com',
        since: '2024-01-01',
        until: '2024-12-31',
        skip: 10,
        count: 25,
      );
      final payload = sender.last!.payload;
      expect(sender.last!.type, MessageType.gitLogSearch);
      expect(payload['query'], 'fix');
      expect(payload['branch'], 'main');
      expect(payload['author'], 'dev@test.com');
      expect(payload['since'], '2024-01-01');
      expect(payload['until'], '2024-12-31');
      expect(payload['skip'], 10);
      expect(payload['count'], 25);
    });

    test('gitDiffFile 发送 staged=false (默认)', () {
      git.gitDiffFile('src/app.py', repo: testRepo);
      final payload = sender.last!.payload;
      expect(sender.last!.type, MessageType.gitDiff);
      expect(payload['path'], 'src/app.py');
      expect(payload['staged'], false);
    });

    test('gitDiffFile 发送 staged=true', () {
      git.gitDiffFile('src/app.py', repo: testRepo, staged: true);
      final payload = sender.last!.payload;
      expect(payload['path'], 'src/app.py');
      expect(payload['staged'], true);
    });
  });
}
