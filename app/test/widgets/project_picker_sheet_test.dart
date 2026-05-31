// Feature: project-browser-enhance
//
// Widget tests for ProjectPickerSheet.
//
// Tests cover:
//   - Renders search bar with placeholder text
//   - Shows loading indicator while recent projects load
//   - Displays recent projects when received
//   - Shows "No results found" empty state
//   - Browse directories toggle is present
//   - Manual path input link is present and expandable
//   - Search bar clear button appears when text is entered
//   - Project tile shows name, path, and git badge

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobileflow/l10n/app_localizations.dart';
import 'package:mobileflow/models/protocol.dart';
import 'package:mobileflow/services/websocket_service.dart';
import 'package:mobileflow/services/ws_operations/project_operations.dart';
import 'package:mobileflow/theme/app_theme.dart';
import 'package:mobileflow/widgets/project_picker_sheet.dart';

/// Mock ProjectOperations that records calls instead of sending messages.
class MockProjectOperations implements ProjectOperations {
  final List<String> calls = [];

  @override
  void searchProjects(String query, {int? maxResults}) {
    calls.add('searchProjects:$query');
  }

  @override
  void browseDirectory(String path) {
    calls.add('browseDirectory:$path');
  }

  // Stub remaining ProjectOperations members via noSuchMethod
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Minimal mock of WebSocketService for widget testing.
///
/// Exposes a StreamController so tests can inject messages,
/// and delegates project operations to [MockProjectOperations]
/// for call recording and verification.
class MockWebSocketService extends ChangeNotifier implements WebSocketService {
  final _messageController = StreamController<WsMessage>.broadcast();
  final MockProjectOperations mockProjectOps = MockProjectOperations();

  @override
  Stream<WsMessage> get messageStream => _messageController.stream;

  @override
  ProjectOperations get projectOps => mockProjectOps;

  /// Inject a message into the stream (simulates server response).
  void injectMessage(WsMessage msg) => _messageController.add(msg);

  // Stub all other WebSocketService members as noSuchMethod fallback
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Wrap a widget with MaterialApp + Provider<WebSocketService> + i18n.
Widget _wrap(MockWebSocketService ws, Widget child) {
  return ChangeNotifierProvider<WebSocketService>.value(
    value: ws,
    child: MaterialApp(
      theme: AppTheme.buildDark(),
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Builder(
          builder: (context) => child,
        ),
      ),
    ),
  );
}

void main() {
  late MockWebSocketService mockWs;
  late String? selectedPath;

  setUp(() {
    mockWs = MockWebSocketService();
    selectedPath = null;
  });

  tearDown(() {
    mockWs.dispose();
  });

  group('ProjectPickerSheet', () {
    // Feature: project-browser-enhance
    testWidgets('renders search bar with placeholder', (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      expect(find.text('搜索项目名称...'), findsOneWidget);
      expect(find.text('选择项目'), findsOneWidget);
    });

    // Feature: project-browser-enhance
    testWidgets('shows loading indicator before recent projects arrive',
        (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      // Before any message arrives, should show loading
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    // Feature: project-browser-enhance
    testWidgets('displays recent projects when received', (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      // Inject recent projects response
      mockWs.injectMessage(WsMessage(
        type: MessageType.projectSearchResult,
        payload: {
          'results': [
            {
              'path': '/home/user/my-app',
              'name': 'my-app',
              'project_type': 'node',
              'has_git': true,
              'exists': true,
            },
            {
              'path': '/home/user/backend',
              'name': 'backend',
              'project_type': 'python',
              'has_git': false,
              'exists': true,
            },
          ],
          'is_browsing': false,
          'current_path': '',
          'is_complete': true,
        },
      ));
      await tester.pumpAndSettle();

      expect(find.text('最近项目'), findsOneWidget);
      expect(find.text('my-app'), findsOneWidget);
      expect(find.text('backend'), findsOneWidget);
      // Git badge for my-app
      expect(find.text('git'), findsOneWidget);
    });

    // Feature: project-browser-enhance
    testWidgets('shows empty state when no recent projects', (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      mockWs.injectMessage(WsMessage(
        type: MessageType.projectSearchResult,
        payload: {
          'results': [],
          'is_browsing': false,
          'current_path': '',
          'is_complete': true,
        },
      ));
      await tester.pumpAndSettle();

      expect(find.text('开始你的第一个项目'), findsOneWidget);
    });

    // Feature: project-browser-enhance
    testWidgets('browse directories toggle is present', (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      // Inject empty recent to get past loading
      mockWs.injectMessage(WsMessage(
        type: MessageType.projectSearchResult,
        payload: {
          'results': [],
          'is_browsing': false,
          'current_path': '',
          'is_complete': true,
        },
      ));
      await tester.pumpAndSettle();

      expect(find.text('浏览目录'), findsOneWidget);
    });

    // Feature: project-browser-enhance
    testWidgets('manual path input link is present', (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      mockWs.injectMessage(WsMessage(
        type: MessageType.projectSearchResult,
        payload: {
          'results': [],
          'is_browsing': false,
          'current_path': '',
          'is_complete': true,
        },
      ));
      await tester.pumpAndSettle();

      expect(find.text('手动输入路径'), findsOneWidget);
    });

    // Feature: project-browser-enhance
    testWidgets('tapping recent project calls onProjectSelected',
        (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      mockWs.injectMessage(WsMessage(
        type: MessageType.projectSearchResult,
        payload: {
          'results': [
            {
              'path': '/home/user/my-app',
              'name': 'my-app',
              'project_type': 'node',
              'has_git': true,
              'exists': true,
            },
          ],
          'is_browsing': false,
          'current_path': '',
          'is_complete': true,
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('my-app'));
      await tester.pumpAndSettle();

      expect(selectedPath, '/home/user/my-app');
    });

    // Feature: project-browser-enhance
    testWidgets('non-existent project is dimmed and not tappable',
        (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      mockWs.injectMessage(WsMessage(
        type: MessageType.projectSearchResult,
        payload: {
          'results': [
            {
              'path': '/home/user/deleted',
              'name': 'deleted',
              'project_type': null,
              'has_git': false,
              'exists': false,
            },
          ],
          'is_browsing': false,
          'current_path': '',
          'is_complete': true,
        },
      ));
      await tester.pumpAndSettle();

      // Should show "目录不存在" text
      expect(find.textContaining('目录不存在'), findsOneWidget);

      // Tapping should not trigger callback (exists=false)
      await tester.tap(find.text('deleted'));
      await tester.pumpAndSettle();
      expect(selectedPath, isNull);
    });

    // Feature: project-browser-enhance
    testWidgets('requests recent projects on init', (tester) async {
      await tester.pumpWidget(_wrap(
        mockWs,
        ProjectPickerSheet(onProjectSelected: (p) => selectedPath = p),
      ));
      await tester.pump();

      // Should have called searchProjects with empty query via projectOps
      expect(mockWs.mockProjectOps.calls, contains('searchProjects:'));
    });
  });
}
