// ChatStateMixin tests
//
// Covers: stream lifecycle, chunk handling (text/thought/diff/tool_use/tool_update/error),
// CLI lifecycle state, history restore, castMapList utility.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/chat_message.dart';
import 'package:mobileflow/models/payloads/cli_payloads.g.dart';
import 'package:mobileflow/services/chat_state.dart';

/// Minimal host class for the mixin under test
class TestChatState extends ChangeNotifier with ChatStateMixin {}

void main() {
  late TestChatState state;

  setUp(() {
    state = TestChatState();
  });

  tearDown(() {
    state.disposeChatState();
    state.dispose();
  });

  group('castMapList', () {
    test('null returns null', () {
      expect(castMapList(null), isNull);
    });

    test('converts dynamic list', () {
      final result = castMapList([
        {'path': 'a.py', 'line': 1},
        {'path': 'b.py'},
      ]);
      expect(result, isNotNull);
      expect(result!.length, 2);
      expect(result[0]['path'], 'a.py');
    });
  });

  group('CliLifecycleState', () {
    test('initial state is uninitialized', () {
      expect(state.cliLifecycleState, CliLifecycleState.uninitialized);
      expect(state.cliStatusMessage, isEmpty);
      expect(state.cliErrorMessage, isNull);
    });

    test('handleCliStatus checking_env', () {
      state.handleCliStatus(CliStatusPayload(cli: '', state: 'checking_env', message: 'Checking...'));
      expect(state.cliLifecycleState, CliLifecycleState.checkingEnv);
      expect(state.cliStatusMessage, 'Checking...');
    });

    test('handleCliStatus starting', () {
      state.handleCliStatus(CliStatusPayload(cli: '', state: 'starting', message: 'Starting...'));
      expect(state.cliLifecycleState, CliLifecycleState.starting);
    });

    test('handleCliStatus ready', () {
      state.handleCliStatus(CliStatusPayload(cli: '', state: 'ready', message: 'Ready'));
      expect(state.cliLifecycleState, CliLifecycleState.ready);
    });

    test('handleCliStatus failed with error', () {
      state.handleCliStatus(CliStatusPayload(
        cli: '',
        state: 'failed',
        message: 'Timeout',
        error: 'timeout_at=starting',
      ));
      expect(state.cliLifecycleState, CliLifecycleState.failed);
      expect(state.cliErrorMessage, 'timeout_at=starting');
    });

    test('handleCliStatus unknown falls back to uninitialized', () {
      state.handleCliStatus(CliStatusPayload(cli: '', state: 'bogus', message: ''));
      expect(state.cliLifecycleState, CliLifecycleState.uninitialized);
    });
  });

  group('Stream lifecycle', () {
    test('beginAssistantMessage adds streaming message', () {
      state.beginAssistantMessage();
      expect(state.messages.length, 1);
      expect(state.messages.first.role, ChatRole.assistant);
      expect(state.messages.first.isStreaming, true);
      expect(state.agentStatus, AgentStatus.thinking);
    });

    test('finishStream marks message as done', () {
      state.beginAssistantMessage();
      state.handleStreamChunk({'type': 'text', 'content': 'hello'});
      state.finishStream(null);
      expect(state.messages.first.isStreaming, false);
      expect(state.agentStatus, AgentStatus.idle);
    });

    test('errorStream adds error block and finishes', () {
      state.beginAssistantMessage();
      state.errorStream('boom', null);
      final blocks = state.messages.first.blocks;
      expect(blocks.any((b) => b.type == BlockType.error), true);
      expect(state.agentStatus, AgentStatus.idle);
    });
  });

  group('handleStreamChunk', () {
    setUp(() {
      state.beginAssistantMessage();
    });

    test('text chunk appends text', () {
      state.handleStreamChunk({'type': 'text', 'content': 'hello '});
      state.handleStreamChunk({'type': 'text', 'content': 'world'});
      state.flushStreamNotify();
      expect(state.messages.first.plainText, 'hello world');
    });

    test('thinking chunk adds thought block', () {
      state.handleStreamChunk({'type': 'thinking', 'content': 'hmm'});
      final blocks = state.messages.first.blocks;
      expect(blocks.any((b) => b.type == BlockType.thought), true);
    });

    test('diff chunk creates fileEdit block', () {
      state.handleStreamChunk({
        'type': 'diff',
        'file_path': 'main.py',
        'old_content': 'old',
        'new_content': 'new',
      });
      final blocks = state.messages.first.blocks;
      final edit = blocks.firstWhere((b) => b.type == BlockType.fileEdit);
      expect(edit.filePath, 'main.py');
      expect(edit.editEntries.length, 1);
    });

    test('diff chunk same file appends entry', () {
      state.handleStreamChunk({
        'type': 'diff',
        'file_path': 'main.py',
        'old_content': 'v1',
        'new_content': 'v2',
      });
      state.handleStreamChunk({
        'type': 'diff',
        'file_path': 'main.py',
        'old_content': 'v2',
        'new_content': 'v3',
      });
      final blocks = state.messages.first.blocks;
      final edits = blocks.where((b) => b.type == BlockType.fileEdit).toList();
      expect(edits.length, 1);
      expect(edits.first.editEntries.length, 2);
    });

    test('tool_use chunk creates toolCall block', () {
      state.handleStreamChunk({
        'type': 'tool_use',
        'content': 'read',
        'kind': 'read',
        'tool_id': 'tc1',
        'tool_input': '/src/main.py',
      });
      final blocks = state.messages.first.blocks;
      final tool = blocks.firstWhere((b) => b.type == BlockType.toolCall);
      expect(tool.toolName, 'read');
      expect(tool.toolId, 'tc1');
      expect(state.agentStatus, AgentStatus.toolRunning);
    });

    test('tool_use merges duplicate toolId', () {
      state.handleStreamChunk({
        'type': 'tool_use',
        'content': 'read',
        'tool_id': 'tc1',
      });
      state.handleStreamChunk({
        'type': 'tool_use',
        'content': 'read file',
        'tool_id': 'tc1',
        'kind': 'read',
      });
      final tools = state.messages.first.blocks
          .where((b) => b.type == BlockType.toolCall)
          .toList();
      expect(tools.length, 1);
      expect(tools.first.toolName, 'read file');
    });

    test('tool_update completes tool', () {
      state.handleStreamChunk({
        'type': 'tool_use',
        'content': 'grep',
        'tool_id': 'tc1',
      });
      state.handleStreamChunk({
        'type': 'tool_update',
        'tool_id': 'tc1',
        'status': 'completed',
      });
      final tool = state.messages.first.blocks
          .firstWhere((b) => b.type == BlockType.toolCall);
      expect(tool.toolStatus, ToolStatus.completed);
      expect(state.agentStatus, AgentStatus.thinking);
    });

    test('error chunk adds error block', () {
      state.handleStreamChunk({'type': 'error', 'content': 'oops'});
      final blocks = state.messages.first.blocks;
      expect(blocks.any((b) => b.type == BlockType.error && b.text == 'oops'), true);
    });

    test('no-op when no current stream message', () {
      state.finishStream(null);
      // Should not crash
      state.handleStreamChunk({'type': 'text', 'content': 'orphan'});
      expect(state.messages.length, 1); // only the finished one
    });
  });

  group('restoreHistory', () {
    test('user messages', () {
      state.restoreHistory([
        {'role': 'user', 'type': 'text', 'content': 'hello'},
        {'role': 'user', 'type': 'text', 'content': 'world'},
      ]);
      expect(state.messages.length, 2);
      expect(state.messages[0].role, ChatRole.user);
      expect(state.messages[1].plainText, 'world');
    });

    test('assistant text messages grouped', () {
      state.restoreHistory([
        {'role': 'assistant', 'type': 'text', 'content': 'part1'},
        {'role': 'assistant', 'type': 'text', 'content': 'part2'},
      ]);
      expect(state.messages.length, 1);
      expect(state.messages.first.role, ChatRole.assistant);
    });

    test('user breaks assistant grouping', () {
      state.restoreHistory([
        {'role': 'assistant', 'type': 'text', 'content': 'a1'},
        {'role': 'user', 'type': 'text', 'content': 'u1'},
        {'role': 'assistant', 'type': 'text', 'content': 'a2'},
      ]);
      expect(state.messages.length, 3);
      expect(state.messages[0].role, ChatRole.assistant);
      expect(state.messages[1].role, ChatRole.user);
      expect(state.messages[2].role, ChatRole.assistant);
    });

    test('tool_use in history', () {
      state.restoreHistory([
        {
          'role': 'assistant',
          'type': 'tool_use',
          'content': 'read',
          'data': {'name': 'read', 'kind': 'read', 'id': 'tc1'},
        },
      ]);
      expect(state.messages.length, 1);
      final blocks = state.messages.first.blocks;
      expect(blocks.first.type, BlockType.toolCall);
      expect(blocks.first.toolStatus, ToolStatus.completed);
    });

    test('thought in history', () {
      state.restoreHistory([
        {'role': 'assistant', 'type': 'thought', 'content': 'thinking...'},
      ]);
      final blocks = state.messages.first.blocks;
      expect(blocks.first.type, BlockType.thought);
    });

    test('empty content user message skipped', () {
      state.restoreHistory([
        {'role': 'user', 'type': 'text', 'content': ''},
      ]);
      expect(state.messages, isEmpty);
    });

    test('clears loading state', () {
      state.loadingHistory = true;
      state.restoreHistory([]);
      expect(state.isLoadingHistory, false);
    });
  });

  group('clearMessages', () {
    test('empties message list', () {
      state.beginAssistantMessage();
      state.handleStreamChunk({'type': 'text', 'content': 'hi'});
      state.finishStream(null);
      state.clearMessages();
      expect(state.messages, isEmpty);
    });
  });
}
