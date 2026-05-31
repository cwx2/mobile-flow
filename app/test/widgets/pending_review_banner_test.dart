// Pending review banner logic tests.
//
// Tests the PendingEdit model and the extraction logic that identifies
// unreviewed file edits from chat messages.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/chat_message.dart';
import 'package:mobileflow/widgets/pending_review_banner.dart';

void main() {
  group('PendingEdit', () {
    test('fileName extracts last path segment', () {
      final edit = PendingEdit(
        filePath: 'src/services/auth.py',
        entry: FileEditEntry(oldContent: 'old', newContent: 'new'),
        block: ContentBlock.fileEdit(
            path: 'src/services/auth.py', oldContent: 'old', newContent: 'new'),
      );
      expect(edit.fileName, 'auth.py');
    });

    test('fileName handles root-level file', () {
      final edit = PendingEdit(
        filePath: 'README.md',
        entry: FileEditEntry(oldContent: '', newContent: '# Hello'),
        block: ContentBlock.fileEdit(
            path: 'README.md', oldContent: '', newContent: '# Hello'),
      );
      expect(edit.fileName, 'README.md');
    });
  });

  group('Pending edit extraction logic', () {
    test('no messages returns empty list', () {
      final pending = extractPendingEdits([]);
      expect(pending, isEmpty);
    });

    test('messages without file edits returns empty', () {
      final messages = [
        ChatMessage(role: ChatRole.user, blocks: [ContentBlock.text('hello')]),
        ChatMessage(
            role: ChatRole.assistant, blocks: [ContentBlock.text('hi')]),
      ];
      final pending = extractPendingEdits(messages);
      expect(pending, isEmpty);
    });

    test('pending file edit is found', () {
      final block = ContentBlock.fileEdit(
          path: 'src/main.py', oldContent: 'old', newContent: 'new');
      final messages = [
        ChatMessage(role: ChatRole.assistant, blocks: [block]),
      ];
      final pending = extractPendingEdits(messages);
      expect(pending.length, 1);
      expect(pending[0].filePath, 'src/main.py');
      expect(pending[0].entry.isPending, true);
    });

    test('accepted edit is not included', () {
      final block = ContentBlock.fileEdit(
          path: 'src/main.py', oldContent: 'old', newContent: 'new');
      block.editEntries[0].accepted = true;
      final messages = [
        ChatMessage(role: ChatRole.assistant, blocks: [block]),
      ];
      final pending = extractPendingEdits(messages);
      expect(pending, isEmpty);
    });

    test('rejected edit is not included', () {
      final block = ContentBlock.fileEdit(
          path: 'src/main.py', oldContent: 'old', newContent: 'new');
      block.editEntries[0].accepted = false;
      final messages = [
        ChatMessage(role: ChatRole.assistant, blocks: [block]),
      ];
      final pending = extractPendingEdits(messages);
      expect(pending, isEmpty);
    });

    test('multiple pending edits across messages', () {
      final block1 = ContentBlock.fileEdit(
          path: 'src/a.py', oldContent: 'a1', newContent: 'a2');
      final block2 = ContentBlock.fileEdit(
          path: 'src/b.py', oldContent: 'b1', newContent: 'b2');
      final messages = [
        ChatMessage(role: ChatRole.assistant, blocks: [block1]),
        ChatMessage(role: ChatRole.assistant, blocks: [block2]),
      ];
      final pending = extractPendingEdits(messages);
      expect(pending.length, 2);
    });

    test('mixed pending and resolved edits', () {
      final block = ContentBlock.fileEdit(
          path: 'src/mix.py', oldContent: 'v1', newContent: 'v2');
      // Add a second edit to the same file
      block.editEntries.add(
          FileEditEntry(oldContent: 'v2', newContent: 'v3'));
      // Accept the first, leave second pending
      block.editEntries[0].accepted = true;

      final messages = [
        ChatMessage(role: ChatRole.assistant, blocks: [block]),
      ];
      final pending = extractPendingEdits(messages);
      expect(pending.length, 1);
      expect(pending[0].entry.newContent, 'v3');
    });

    test('file edit block without filePath is skipped', () {
      final block = ContentBlock(type: BlockType.fileEdit);
      // filePath is null
      final messages = [
        ChatMessage(role: ChatRole.assistant, blocks: [block]),
      ];
      final pending = extractPendingEdits(messages);
      expect(pending, isEmpty);
    });
  });

  group('FileEditEntry status', () {
    test('isPending when accepted is null', () {
      final entry = FileEditEntry(oldContent: 'a', newContent: 'b');
      expect(entry.isPending, true);
      expect(entry.isAccepted, false);
      expect(entry.isRejected, false);
    });

    test('isAccepted when accepted is true', () {
      final entry =
          FileEditEntry(oldContent: 'a', newContent: 'b', accepted: true);
      expect(entry.isPending, false);
      expect(entry.isAccepted, true);
    });

    test('isRejected when accepted is false', () {
      final entry =
          FileEditEntry(oldContent: 'a', newContent: 'b', accepted: false);
      expect(entry.isPending, false);
      expect(entry.isRejected, true);
    });

    test('linesAdded counts correctly', () {
      final entry = FileEditEntry(
        oldContent: 'line1\nline2',
        newContent: 'line1\nline2\nline3\nline4',
      );
      expect(entry.linesAdded, 2);
      expect(entry.linesDeleted, 0);
    });

    test('linesDeleted counts correctly', () {
      final entry = FileEditEntry(
        oldContent: 'line1\nline2\nline3',
        newContent: 'line1',
      );
      expect(entry.linesAdded, 0);
      expect(entry.linesDeleted, 2);
    });
  });
}

/// Extract pending edits from messages (same logic as PendingReviewBanner).
///
/// Extracted as a pure function for testability without needing
/// a full widget tree or WebSocketService mock.
List<PendingEdit> extractPendingEdits(List<ChatMessage> messages) {
  final pending = <PendingEdit>[];
  for (final msg in messages) {
    for (final block in msg.blocks) {
      if (block.type == BlockType.fileEdit && block.filePath != null) {
        for (final entry in block.editEntries) {
          if (entry.isPending) {
            pending.add(PendingEdit(
              filePath: block.filePath!,
              entry: entry,
              block: block,
            ));
          }
        }
      }
    }
  }
  return pending;
}
