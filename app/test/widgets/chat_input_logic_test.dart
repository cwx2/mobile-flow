// 聊天输入栏逻辑测试
//
// 测试范围：
//   - InputHistory（输入历史管理）
//   - QueuedMessage（排队消息模型）
//   - ChatAttachment（附件模型）
//   - SlashCommand 过滤逻辑
//   - Token 估算逻辑

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/utils/input_history.dart';
import 'package:mobileflow/widgets/chat_input_bar.dart';
import 'package:mobileflow/widgets/slash_command_menu.dart';

void main() {
  group('InputHistory', () {
    test('空历史返回 null', () {
      final history = InputHistory();
      expect(history.previous(''), isNull);
      expect(history.next(), isNull);
    });

    test('push 后可以 previous 取回', () async {
      final history = InputHistory();
      await history.push('hello');
      expect(history.previous(''), 'hello');
    });

    test('多条历史按顺序返回（最新的先）', () async {
      final history = InputHistory();
      await history.push('first');
      await history.push('second');
      await history.push('third');
      expect(history.previous(''), 'third');
      expect(history.previous(''), 'second');
      expect(history.previous(''), 'first');
    });

    test('到顶后继续 previous 返回 null', () async {
      final history = InputHistory();
      await history.push('only');
      expect(history.previous(''), 'only');
      expect(history.previous(''), isNull);
    });

    test('next 可以向下翻', () async {
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

    test('reset 重置游标', () async {
      final history = InputHistory();
      await history.push('a');
      await history.push('b');
      history.previous('');
      history.reset();
      expect(history.previous(''), 'b');
    });

    test('空字符串不记录', () async {
      final history = InputHistory();
      await history.push('');
      await history.push('   ');
      expect(history.previous(''), isNull);
    });

    test('重复内容增加 useCount 而非新增', () async {
      final history = InputHistory();
      await history.push('same');
      await history.push('same');
      await history.push('same');
      // Only one entry, but useCount = 3
      expect(history.entries.length, 1);
      expect(history.entries.first.useCount, 3);
      expect(history.previous(''), 'same');
      expect(history.previous(''), isNull);
    });

    test('不同内容各自独立', () async {
      final history = InputHistory();
      await history.push('a');
      await history.push('b');
      expect(history.entries.length, 2);
    });

    test('next 在未 previous 时返回 null', () async {
      final history = InputHistory();
      await history.push('a');
      expect(history.next(), isNull);
    });

    test('超过 50 条淘汰最低频的', () async {
      final history = InputHistory();
      // Push 50 unique entries
      for (int i = 0; i < 50; i++) {
        await history.push('entry_$i');
      }
      // Boost entry_0 so it won't be evicted
      await history.push('entry_0');
      // Push one more to trigger eviction
      await history.push('new_entry');
      expect(history.entries.length, 50);
      // entry_0 should survive (useCount=2), entry_1 should be evicted (useCount=1, oldest)
      expect(history.entries.any((e) => e.text == 'entry_0'), isTrue);
      expect(history.entries.any((e) => e.text == 'new_entry'), isTrue);
      expect(history.entries.any((e) => e.text == 'entry_1'), isFalse);
    });

    test('entries 返回不可变列表', () async {
      final history = InputHistory();
      await history.push('a');
      final entries = history.entries;
      expect(() => (entries as List).add(HistoryEntry(text: 'b')), throwsUnsupportedError);
    });
  });

  group('QueuedMessage', () {
    test('自动生成 id', () {
      final msg = QueuedMessage(text: 'hello');
      expect(msg.id, isNotEmpty);
    });

    test('自定义 id', () {
      final msg = QueuedMessage(id: 'custom-id', text: 'hello');
      expect(msg.id, 'custom-id');
    });

    test('默认无附件', () {
      final msg = QueuedMessage(text: 'hello');
      expect(msg.attachments, isEmpty);
    });

    test('带附件', () {
      final att = ChatAttachment(
        id: 'att1',
        path: '/tmp/img.jpg',
        mimeType: 'image/jpeg',
      );
      final msg = QueuedMessage(text: 'look', attachments: [att]);
      expect(msg.attachments.length, 1);
      expect(msg.attachments[0].id, 'att1');
    });

    test('两个消息 id 不同', () {
      final a = QueuedMessage(text: 'a');
      final b = QueuedMessage(text: 'b');
      expect(a.id, isNot(equals(b.id)));
    });
  });

  group('ChatAttachment', () {
    test('属性正确', () {
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

  // SlashCommand filtering tests use a static test list since
  // getBuiltinSlashCommands() requires BuildContext for i18n.
  // The filtering logic is the same regardless of description text.
  final testSlashCommands = [
    SlashCommand(name: 'new', description: 'New session', icon: Icons.add_comment_outlined, category: SlashCommandCategory.session, immediate: true),
    SlashCommand(name: 'clear', description: 'Clear chat', icon: Icons.delete_outline, category: SlashCommandCategory.session, immediate: true),
    SlashCommand(name: 'history', description: 'View history', icon: Icons.history, category: SlashCommandCategory.session, immediate: true),
    SlashCommand(name: 'files', description: 'View files', icon: Icons.folder_outlined, category: SlashCommandCategory.tools, immediate: true),
    SlashCommand(name: 'terminal', description: 'Open terminal', icon: Icons.terminal, category: SlashCommandCategory.tools, immediate: true),
    SlashCommand(name: 'diff', description: 'View changes', icon: Icons.difference_outlined, category: SlashCommandCategory.tools, immediate: true),
    SlashCommand(name: 'model', description: 'Switch model', icon: Icons.psychology_outlined, category: SlashCommandCategory.config, args: '<model_name>'),
    SlashCommand(name: 'project', description: 'Switch project', icon: Icons.folder_special_outlined, category: SlashCommandCategory.config, immediate: true),
  ];

  group('SlashCommand 过滤', () {
    test('空过滤返回所有命令', () {
      final filtered = testSlashCommands.where((cmd) {
        return cmd.name.toLowerCase().startsWith('');
      }).toList();
      expect(filtered.length, testSlashCommands.length);
    });

    test('过滤 "n" 匹配 new', () {
      final filtered = testSlashCommands.where((cmd) {
        return cmd.name.toLowerCase().startsWith('n');
      }).toList();
      expect(filtered.any((c) => c.name == 'new'), true);
    });

    test('过滤 "cl" 匹配 clear', () {
      final filtered = testSlashCommands.where((cmd) {
        return cmd.name.toLowerCase().startsWith('cl');
      }).toList();
      expect(filtered.length, 1);
      expect(filtered[0].name, 'clear');
    });

    test('过滤 "xyz" 无匹配', () {
      final filtered = testSlashCommands.where((cmd) {
        return cmd.name.toLowerCase().startsWith('xyz');
      }).toList();
      expect(filtered, isEmpty);
    });

    test('大小写不敏感', () {
      final filtered = testSlashCommands.where((cmd) {
        return cmd.name.toLowerCase().startsWith('NEW'.toLowerCase());
      }).toList();
      expect(filtered.any((c) => c.name == 'new'), true);
    });

    test('所有命令有 name 和 description', () {
      for (final cmd in testSlashCommands) {
        expect(cmd.name, isNotEmpty);
        expect(cmd.description, isNotEmpty);
      }
    });

    test('immediate 命令没有 args', () {
      final newCmd = testSlashCommands.firstWhere((c) => c.name == 'new');
      expect(newCmd.immediate, true);
      expect(newCmd.args, isNull);
    });

    test('model 命令有 args', () {
      final modelCmd = testSlashCommands.firstWhere((c) => c.name == 'model');
      expect(modelCmd.args, isNotNull);
      expect(modelCmd.immediate, false);
    });
  });

  group('SlashCommand 分类', () {
    test('三个分类都有命令', () {
      final categories = testSlashCommands.map((c) => c.category).toSet();
      expect(categories.contains(SlashCommandCategory.session), true);
      expect(categories.contains(SlashCommandCategory.tools), true);
      expect(categories.contains(SlashCommandCategory.config), true);
    });
  });

  group('Token 估算', () {
    // 参考 IDE：~1 token per 4 chars，100 字符以下不显示
    test('短文本返回 null', () {
      expect(_tokenEstimate('hello'), isNull);
      expect(_tokenEstimate('a' * 99), isNull);
    });

    test('100 字符返回估算', () {
      expect(_tokenEstimate('a' * 100), '~25 tokens');
    });

    test('400 字符返回 ~100 tokens', () {
      expect(_tokenEstimate('a' * 400), '~100 tokens');
    });

    test('奇数长度向上取整', () {
      expect(_tokenEstimate('a' * 101), '~26 tokens');
    });
  });

  group('isChatStopCommand', () {
    test('识别 stop 命令', () {
      expect(isChatStopCommand('stop'), true);
      expect(isChatStopCommand('/stop'), true);
      expect(isChatStopCommand('esc'), true);
      expect(isChatStopCommand('abort'), true);
      expect(isChatStopCommand('wait'), true);
      expect(isChatStopCommand('exit'), true);
    });

    test('大小写不敏感', () {
      expect(isChatStopCommand('STOP'), true);
      expect(isChatStopCommand('Stop'), true);
      expect(isChatStopCommand('/STOP'), true);
    });

    test('前后空格忽略', () {
      expect(isChatStopCommand('  stop  '), true);
      expect(isChatStopCommand(' /stop '), true);
    });

    test('非 stop 命令返回 false', () {
      expect(isChatStopCommand('hello'), false);
      expect(isChatStopCommand('stopping'), false);
      expect(isChatStopCommand('/new'), false);
      expect(isChatStopCommand(''), false);
    });
  });
}

/// Token 估算（从 ChatInputBar 提取的纯函数版本，用于测试）
String? _tokenEstimate(String text) {
  if (text.length < 100) return null;
  return '~${(text.length / 4).ceil()} tokens';
}
