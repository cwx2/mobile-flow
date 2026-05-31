import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/diff/diff_engine.dart';
import 'package:mobileflow/diff/diff_model.dart';

void main() {
  const engine = DiffEngine(contextLines: 3);

  group('基础 diff', () {
    test('相同文本无变化', () {
      final result = engine.compute('hello\nworld', 'hello\nworld');
      expect(result.hasChanges, false);
      expect(result.totalAdded, 0);
      expect(result.totalDeleted, 0);
    });

    test('新增一行', () {
      final result = engine.compute('a\nb', 'a\nb\nc');
      expect(result.totalAdded, 1);
      expect(result.totalDeleted, 0);
      final added = result.allLines.where((l) => l.type == DiffLineType.added);
      expect(added.length, 1);
      expect(added.first.text, 'c');
    });

    test('删除一行', () {
      final result = engine.compute('a\nb\nc', 'a\nc');
      expect(result.totalDeleted, 1);
      expect(result.totalAdded, 0);
      final deleted =
          result.allLines.where((l) => l.type == DiffLineType.deleted);
      expect(deleted.length, 1);
      expect(deleted.first.text, 'b');
    });

    test('修改一行（删除旧 + 新增新）', () {
      final result = engine.compute('a\nold\nc', 'a\nnew\nc');
      expect(result.totalDeleted, 1);
      expect(result.totalAdded, 1);
    });

    test('空文本到有内容', () {
      final result = engine.compute('', 'hello\nworld');
      expect(result.totalAdded, 2);
      expect(result.totalDeleted, 0);
    });

    test('有内容到空文本', () {
      final result = engine.compute('hello\nworld', '');
      expect(result.totalDeleted, 2);
      expect(result.totalAdded, 0);
    });
  });

  group('行号', () {
    test('上下文行有双行号', () {
      final result = engine.compute('a\nb\nc', 'a\nB\nc');
      final contextLines =
          result.allLines.where((l) => l.type == DiffLineType.context);
      for (final line in contextLines) {
        expect(line.oldLineNum, isNotNull);
        expect(line.newLineNum, isNotNull);
      }
    });

    test('删除行只有旧行号', () {
      final result = engine.compute('a\nb\nc', 'a\nc');
      final deleted =
          result.allLines.firstWhere((l) => l.type == DiffLineType.deleted);
      expect(deleted.oldLineNum, isNotNull);
      expect(deleted.newLineNum, isNull);
    });

    test('新增行只有新行号', () {
      final result = engine.compute('a\nc', 'a\nb\nc');
      final added =
          result.allLines.firstWhere((l) => l.type == DiffLineType.added);
      expect(added.oldLineNum, isNull);
      expect(added.newLineNum, isNotNull);
    });
  });

  group('字符级 diff', () {
    test('修改行有字符级变化', () {
      final result = engine.compute('hello world', 'hello dart');
      final deleted =
          result.allLines.firstWhere((l) => l.type == DiffLineType.deleted);
      final added =
          result.allLines.firstWhere((l) => l.type == DiffLineType.added);
      expect(deleted.charChanges, isNotEmpty);
      expect(added.charChanges, isNotEmpty);
    });

    test('字符级变化位置正确', () {
      final result = engine.compute('abc123xyz', 'abc456xyz');
      final deleted =
          result.allLines.firstWhere((l) => l.type == DiffLineType.deleted);
      // "123" 在位置 3-6 变成了 "456"
      expect(deleted.charChanges.length, 1);
      expect(deleted.charChanges[0].start, 3);
      expect(deleted.charChanges[0].end, 6);
    });

    test('前缀变化', () {
      final result = engine.compute('XXXhello', 'YYYhello');
      final deleted =
          result.allLines.firstWhere((l) => l.type == DiffLineType.deleted);
      expect(deleted.charChanges[0].start, 0);
      expect(deleted.charChanges[0].end, 3);
    });

    test('后缀变化', () {
      final result = engine.compute('helloXXX', 'helloYYY');
      final deleted =
          result.allLines.firstWhere((l) => l.type == DiffLineType.deleted);
      expect(deleted.charChanges[0].start, 5);
      expect(deleted.charChanges[0].end, 8);
    });
  });

  group('Hunk 分组', () {
    test('单个变化生成一个 hunk', () {
      final result = engine.compute('a\nb\nc', 'a\nB\nc');
      expect(result.hunks.length, 1);
    });

    test('远距离变化生成多个 hunks', () {
      // 20 行，第 2 行和第 18 行变化（间隔 > 2*contextLines+1=7）
      final old = List.generate(20, (i) => 'line$i').join('\n');
      final nw =
          old.replaceAll('line1', 'LINE1').replaceAll('line18', 'LINE18');
      final result = engine.compute(old, nw);
      expect(result.hunks.length, 2);
    });

    test('hunk 包含上下文行', () {
      final lines = List.generate(20, (i) => 'line$i');
      final oldText = lines.join('\n');
      final newLines = List.from(lines);
      newLines[10] = 'CHANGED';
      final newText = newLines.join('\n');
      final result = engine.compute(oldText, newText);
      expect(result.hunks.length, 1);
      // 应该有 contextLines 行上下文 + 1 删除 + 1 新增 + contextLines 行上下文
      final hunk = result.hunks[0];
      final contextCount =
          hunk.lines.where((l) => l.type == DiffLineType.context).length;
      expect(contextCount, lessThanOrEqualTo(6)); // 最多 2 * contextLines
    });
  });

  group('边界情况', () {
    test('单行文本', () {
      final result = engine.compute('old', 'new');
      expect(result.totalDeleted, 1);
      expect(result.totalAdded, 1);
    });

    test('多行新增到空文件', () {
      final result = engine.compute('', 'a\nb\nc\nd\ne');
      expect(result.totalAdded, 5);
    });

    test('大文件性能（1000 行）', () {
      final old = List.generate(1000, (i) => 'line $i content here').join('\n');
      final nw = old.replaceAll('line 500', 'MODIFIED 500');
      final sw = Stopwatch()..start();
      final result = engine.compute(old, nw);
      sw.stop();
      expect(result.hasChanges, true);
      // 应该在 1 秒内完成
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });
}
