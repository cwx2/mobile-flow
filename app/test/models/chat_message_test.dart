// ChatMessage and ContentBlock model tests
//
// Covers: construction, appendText, addBlock, plainText, updateToolStatus,
// finalizeAllTools, factory methods, FileEditEntry calculations.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('default construction', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      expect(msg.role, ChatRole.assistant);
      expect(msg.blocks, isEmpty);
      expect(msg.isStreaming, false);
      expect(msg.id, isNotEmpty);
    });

    test('appendText creates text block', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      msg.appendText('hello');
      expect(msg.blocks.length, 1);
      expect(msg.blocks.first.type, BlockType.text);
      expect(msg.blocks.first.text, 'hello');
    });

    test('appendText merges consecutive text', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      msg.appendText('hello ');
      msg.appendText('world');
      expect(msg.blocks.length, 1);
      expect(msg.blocks.first.text, 'hello world');
    });

    test('appendText does not merge after non-text block', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      msg.appendText('before');
      msg.addBlock(ContentBlock.error('oops'));
      msg.appendText('after');
      expect(msg.blocks.length, 3);
      expect(msg.blocks[0].text, 'before');
      expect(msg.blocks[2].text, 'after');
    });

    test('plainText joins text blocks', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      msg.appendText('line1');
      msg.addBlock(ContentBlock.thought('thinking'));
      msg.appendText('line2');
      expect(msg.plainText, 'line1\nline2');
    });

    test('updateToolStatus by id', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      msg.addBlock(ContentBlock.toolCall(name: 'read', id: 'tc1'));
      msg.updateToolStatus('tc1', 'completed');
      expect(msg.blocks.first.toolStatus, ToolStatus.completed);
    });

    test('updateToolStatus fallback to last running', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      msg.addBlock(ContentBlock.toolCall(name: 'a', id: 'tc1'));
      msg.addBlock(ContentBlock.toolCall(name: 'b', id: 'tc2'));
      msg.updateToolStatus('', 'failed');
      // Should update the last running tool (tc2)
      expect(msg.blocks[1].toolStatus, ToolStatus.failed);
    });

    test('updateToolStatus with content blocks', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      msg.addBlock(ContentBlock.toolCall(name: 'search', id: 'tc1'));
      msg.updateToolStatus('tc1', 'completed', contentBlocks: [
        {'type': 'raw_output', 'data': 'results'}
      ]);
      expect(msg.blocks.first.contentBlocks, isNotNull);
      expect(msg.blocks.first.contentBlocks!.length, 1);
    });

    test('finalizeAllTools marks running as completed', () {
      final msg = ChatMessage(role: ChatRole.assistant);
      msg.addBlock(ContentBlock.toolCall(name: 'a', id: 'tc1'));
      msg.addBlock(ContentBlock.toolCall(name: 'b', id: 'tc2'));
      msg.blocks[0].toolStatus = ToolStatus.completed;
      msg.finalizeAllTools();
      expect(msg.blocks[0].toolStatus, ToolStatus.completed);
      expect(msg.blocks[1].toolStatus, ToolStatus.completed);
    });
  });

  group('ContentBlock factories', () {
    test('text', () {
      final b = ContentBlock.text('hello');
      expect(b.type, BlockType.text);
      expect(b.text, 'hello');
    });

    test('thought', () {
      final b = ContentBlock.thought('hmm');
      expect(b.type, BlockType.thought);
      expect(b.text, 'hmm');
    });

    test('error', () {
      final b = ContentBlock.error('boom');
      expect(b.type, BlockType.error);
      expect(b.text, 'boom');
    });

    test('toolCall', () {
      final b = ContentBlock.toolCall(
        name: 'read',
        kind: 'read',
        id: 'tc1',
        toolInput: '/src/main.py',
      );
      expect(b.type, BlockType.toolCall);
      expect(b.toolName, 'read');
      expect(b.toolKind, 'read');
      expect(b.toolId, 'tc1');
      expect(b.toolStatus, ToolStatus.running);
      expect(b.toolProgress, '/src/main.py');
    });

    test('fileEdit creates entry', () {
      final b = ContentBlock.fileEdit(
        path: 'main.py',
        oldContent: 'old',
        newContent: 'new',
      );
      expect(b.type, BlockType.fileEdit);
      expect(b.filePath, 'main.py');
      expect(b.editEntries.length, 1);
      expect(b.editEntries.first.oldContent, 'old');
      expect(b.editEntries.first.newContent, 'new');
    });

    test('plan', () {
      final b = ContentBlock.plan([
        PlanEntry(title: 'Step 1', status: 'completed'),
        PlanEntry(title: 'Step 2', status: 'pending'),
      ]);
      expect(b.type, BlockType.plan);
      expect(b.planEntries!.length, 2);
    });

    test('code', () {
      final b = ContentBlock.code('print("hi")', language: 'python');
      expect(b.type, BlockType.code);
      expect(b.text, 'print("hi")');
      expect(b.language, 'python');
    });
  });

  group('ContentBlock.updateStatus', () {
    test('completed', () {
      final b = ContentBlock.toolCall(name: 'test', id: 'tc1');
      b.updateStatus('completed');
      expect(b.toolStatus, ToolStatus.completed);
    });

    test('failed', () {
      final b = ContentBlock.toolCall(name: 'test', id: 'tc1');
      b.updateStatus('failed');
      expect(b.toolStatus, ToolStatus.failed);
    });

    test('progress appends', () {
      final b = ContentBlock.toolCall(name: 'test', id: 'tc1', toolInput: 'start');
      b.updateStatus('running', progress: ' more');
      expect(b.toolProgress, 'start more');
    });
  });

  group('FileEditEntry', () {
    test('lines added', () {
      final e = FileEditEntry(oldContent: 'a\nb', newContent: 'a\nb\nc\nd');
      expect(e.linesAdded, 2);
      expect(e.linesDeleted, 0);
    });

    test('lines deleted', () {
      final e = FileEditEntry(oldContent: 'a\nb\nc', newContent: 'a');
      expect(e.linesAdded, 0);
      expect(e.linesDeleted, 2);
    });

    test('pending state', () {
      final e = FileEditEntry(oldContent: '', newContent: '');
      expect(e.isPending, true);
      expect(e.isAccepted, false);
      expect(e.isRejected, false);
    });

    test('accepted state', () {
      final e = FileEditEntry(oldContent: '', newContent: '', accepted: true);
      expect(e.isAccepted, true);
      expect(e.isPending, false);
    });
  });
}
