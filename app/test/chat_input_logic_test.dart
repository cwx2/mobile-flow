// Chat input bar logic tests.
//
// Scope:
//   - InputHistory (input history management)
//   - QueuedMessage (queued message model)
//   - ChatAttachment (attachment model)
//   - SlashCommand model structure
//   - Token estimation logic
//   - isChatStopCommand detection

import 'package:flutter/widgets.dart' show IconData;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/utils/input_history.dart';
import 'package:mobileflow/widgets/chat_input_bar.dart';
import 'package:mobileflow/widgets/slash_command_menu.dart';

void main() {
  group('InputHistory', () {
    test('empty history returns null', () {
      final history = InputHistory();
      expect(history.previous(''), isNull);
      expect(history.next(), isNull);
    });

    test('push then previous retrieves it', () async {
      final history = InputHistory();
      await history.push('hello');
      expect(history.previous(''), 'hello');
    });

    test('multiple entries return most recent first', () async {
      final history = InputHistory();
      await history.push('first');
      await history.push('second');
      await history.push('third');
      expect(history.previous(''), 'third');
      expect(history.previous(''), 'second');
      expect(history.previous(''), 'first');
    });

    test('previous returns null at end of history', () async {
      final history = InputHistory();
      await history.push('only');
      expect(history.previous(''), 'only');
      expect(history.previous(''), isNull);
    });

    test('next navigates forward', () async {
      final history = InputHistory();
      await history.push('a');
      await history.push('b');
      await history.push('c');
      history.previous('');
      history.previous('');
      history.previous('');
      expect(history.next(), 'b');
      expect(history.next(), 'c');
      expect(history.next(), '');
    });

    test('reset resets cursor', () async {
      final history = InputHistory();
      await history.push('a');
      await history.push('b');
      history.previous('');
      history.reset();
      expect(history.previous(''), 'b');
    });

    test('empty string not recorded', () async {
      final history = InputHistory();
      await history.push('');
      await history.push('   ');
      expect(history.previous(''), isNull);
    });

    test('duplicate content deduplicates', () async {
      final history = InputHistory();
      await history.push('same');
      await history.push('same');
      await history.push('same');
      expect(history.previous(''), 'same');
      expect(history.previous(''), isNull);
    });

    test('next without previous returns null', () async {
      final history = InputHistory();
      await history.push('a');
      expect(history.next(), isNull);
    });

    test('over 50 entries evicts least used', () async {
      final history = InputHistory();
      for (int i = 0; i < 60; i++) {
        await history.push('entry_$i');
      }
      // Should have at most 50 entries
      expect(history.entries.length, 50);
    });

    test('entries returns unmodifiable list', () async {
      final history = InputHistory();
      await history.push('a');
      final entries = history.entries;
      expect(() => (entries as List).add(HistoryEntry(text: 'b')),
          throwsUnsupportedError);
    });
  });

  group('QueuedMessage', () {
    test('auto-generates id', () {
      final msg = QueuedMessage(text: 'hello');
      expect(msg.id, isNotEmpty);
    });

    test('custom id', () {
      final msg = QueuedMessage(id: 'custom-id', text: 'hello');
      expect(msg.id, 'custom-id');
    });

    test('default no attachments', () {
      final msg = QueuedMessage(text: 'hello');
      expect(msg.attachments, isEmpty);
    });

    test('with attachments', () {
      final att = ChatAttachment(
        id: 'att1',
        path: '/tmp/img.jpg',
        mimeType: 'image/jpeg',
      );
      final msg = QueuedMessage(text: 'look', attachments: [att]);
      expect(msg.attachments.length, 1);
      expect(msg.attachments[0].id, 'att1');
    });

    test('two messages have different ids', () {
      final a = QueuedMessage(text: 'a');
      final b = QueuedMessage(text: 'b');
      expect(a.id, isNot(equals(b.id)));
    });
  });

  group('ChatAttachment', () {
    test('properties correct', () {
      const att = ChatAttachment(
        id: 'x',
        path: '/path/to/file.png',
        mimeType: 'image/png',
      );
      expect(att.id, 'x');
      expect(att.path, '/path/to/file.png');
      expect(att.mimeType, 'image/png');
    });
  });

  group('SlashCommand model', () {
    test('SlashCommand has required fields', () {
      const cmd = SlashCommand(
        name: 'test',
        description: 'A test command',
        icon: IconData(0xe5ca),
        category: SlashCommandCategory.tools,
      );
      expect(cmd.name, 'test');
      expect(cmd.description, 'A test command');
      expect(cmd.category, SlashCommandCategory.tools);
      expect(cmd.immediate, false);
      expect(cmd.args, isNull);
    });

    test('SlashCommand immediate flag', () {
      const cmd = SlashCommand(
        name: 'new',
        description: 'New session',
        icon: IconData(0xe145),
        category: SlashCommandCategory.session,
        immediate: true,
      );
      expect(cmd.immediate, true);
    });

    test('SlashCommandCategory has all values', () {
      expect(SlashCommandCategory.values.length, greaterThanOrEqualTo(3));
      expect(SlashCommandCategory.values.contains(SlashCommandCategory.session), true);
      expect(SlashCommandCategory.values.contains(SlashCommandCategory.tools), true);
      expect(SlashCommandCategory.values.contains(SlashCommandCategory.config), true);
    });
  });

  group('Token estimation', () {
    test('short text returns null', () {
      expect(_tokenEstimate('hello'), isNull);
      expect(_tokenEstimate('a' * 99), isNull);
    });

    test('100 chars returns estimate', () {
      expect(_tokenEstimate('a' * 100), '~25 tokens');
    });

    test('400 chars returns ~100 tokens', () {
      expect(_tokenEstimate('a' * 400), '~100 tokens');
    });

    test('odd length rounds up', () {
      expect(_tokenEstimate('a' * 101), '~26 tokens');
    });
  });

  group('isChatStopCommand', () {
    test('recognizes stop commands', () {
      expect(isChatStopCommand('stop'), true);
      expect(isChatStopCommand('/stop'), true);
      expect(isChatStopCommand('esc'), true);
      expect(isChatStopCommand('abort'), true);
      expect(isChatStopCommand('wait'), true);
      expect(isChatStopCommand('exit'), true);
    });

    test('case insensitive', () {
      expect(isChatStopCommand('STOP'), true);
      expect(isChatStopCommand('Stop'), true);
      expect(isChatStopCommand('/STOP'), true);
    });

    test('trims whitespace', () {
      expect(isChatStopCommand('  stop  '), true);
      expect(isChatStopCommand(' /stop '), true);
    });

    test('non-stop commands return false', () {
      expect(isChatStopCommand('hello'), false);
      expect(isChatStopCommand('stopping'), false);
      expect(isChatStopCommand('/new'), false);
      expect(isChatStopCommand(''), false);
    });
  });
}

/// Token estimation (pure function extracted from ChatInputBar for testing).
String? _tokenEstimate(String text) {
  if (text.length < 100) return null;
  return '~${(text.length / 4).ceil()} tokens';
}
