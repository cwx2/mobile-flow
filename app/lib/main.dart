/// main.dart — App entry point, Provider injection, and theme initialization.
///
/// Builds ThemeData via AppTheme (with ThemeExtension token layer)
/// and supports smooth theme switching via AnimatedTheme.
/// Routes to ConnectScreen or HomeScreen based on connection state.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import 'core/event_bus.dart';
import 'debug/debug_server.dart';
import 'l10n/app_localizations.dart';
import 'services/git_state.dart';
import 'services/locale_service.dart';
import 'services/websocket_service.dart';
import 'services/connection_service.dart';
import 'services/ws_operations/chat_operations.dart';
import 'services/ws_operations/file_operations.dart';
import 'services/ws_operations/git_operations.dart';
import 'services/ws_operations/cli_operations.dart';
import 'services/ws_operations/project_operations.dart';
import 'services/ws_operations/terminal_operations.dart';
import 'services/ws_operations/plugin_operations.dart';
import 'services/ws_operations/permission_operations.dart';
import 'services/ws_operations/test_panel_operations.dart';
import 'services/ws_operations/run_config_operations.dart';
import 'services/run_config_provider.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'theme/code_theme.dart';
import 'utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize structured logging (must be first)
  initLogging();
  // Load saved language preference before building the widget tree
  final localeNotifier = LocaleNotifier();
  await localeNotifier.load();
  // Start debug element coordinate server (port 9601) in debug mode
  if (kDebugMode) {
    startDebugServer();
  }
  // Force-enable Semantics tree so Android accessibility tools
  // (uiautomator, TalkBack) can see Flutter widgets. Required for
  // automated UI testing via adb MCP tools.
  SemanticsBinding.instance.ensureSemantics();
  runApp(MobileFlowApp(localeNotifier: localeNotifier));
}

/// Theme mode manager (dark/light toggle).
///
/// Exposes the current [ThemeData] built by [AppTheme] and notifies
/// listeners on mode change.
class ThemeNotifier extends ChangeNotifier {
  bool _isDark = true;

  bool get isDark => _isDark;
  ThemeData get theme => _isDark ? AppTheme.buildDark() : AppTheme.buildDawn();

  /// Toggle between dark and light mode.
  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }

  /// Set dark mode explicitly.
  void setDark(bool dark) {
    if (_isDark == dark) return;
    _isDark = dark;
    notifyListeners();
  }
}

/// Root application widget with Provider injection and theme initialization.
class MobileFlowApp extends StatelessWidget {
  final LocaleNotifier localeNotifier;

  const MobileFlowApp({super.key, required this.localeNotifier});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionService()),
        ChangeNotifierProvider(create: (_) => AppEventBus()),
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider(create: (_) => CodeThemeNotifier()),
        ChangeNotifierProvider.value(value: localeNotifier),
        ChangeNotifierProxyProvider2<ConnectionService, AppEventBus,
            WebSocketService>(
          create: (_) => WebSocketService(),
          update: (_, connection, eventBus, ws) {
            ws?.updateConnection(connection);
            ws?.updateEventBus(eventBus);
            return ws!;
          },
        ),
        // Operations (derived from WebSocketService, not ChangeNotifiers)
        ProxyProvider<WebSocketService, ChatOperations>(
          update: (_, ws, __) => ws.chatOps,
        ),
        ProxyProvider<WebSocketService, FileOperations>(
          update: (_, ws, __) => ws.fileOps,
        ),
        ProxyProvider<WebSocketService, GitOperations>(
          update: (_, ws, __) => ws.gitOps,
        ),
        ProxyProvider<WebSocketService, CliOperations>(
          update: (_, ws, __) => ws.cliOps,
        ),
        ProxyProvider<WebSocketService, ProjectOperations>(
          update: (_, ws, __) => ws.projectOps,
        ),
        ProxyProvider<WebSocketService, TerminalOperations>(
          update: (_, ws, __) => ws.terminalOps,
        ),
        ProxyProvider<WebSocketService, PluginOperations>(
          update: (_, ws, __) => ws.pluginOps,
        ),
        ProxyProvider<WebSocketService, PermissionOperations>(
          update: (_, ws, __) => ws.permissionOps,
        ),
        ProxyProvider<WebSocketService, TestPanelOperations>(
          update: (_, ws, __) => ws.testPanelOps,
        ),
        ProxyProvider<WebSocketService, RunConfigOperations>(
          update: (_, ws, __) => ws.runConfigOps,
        ),
        ChangeNotifierProvider(create: (_) => RunConfigProvider()),
        // Git state (unchanged)
        ChangeNotifierProxyProvider2<WebSocketService, AppEventBus,
            GitStateProvider>(
          create: (_) => GitStateProvider(),
          update: (_, ws, eventBus, git) {
            git?.bind(ws, eventBus);
            return git!;
          },
        ),
      ],
      child: Consumer2<ThemeNotifier, LocaleNotifier>(
        builder: (_, themeNotifier, localeNotifier, __) => MaterialApp(
          title: 'MobileFlow',
          debugShowCheckedModeBanner: false,
          theme: themeNotifier.theme,
          locale: localeNotifier.locale,
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: const AppRouter(),
        ),
      ),
    );
  }
}

/// Routes to the appropriate screen based on connection state (with splash animation).
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    // Splash animation not done → show SplashScreen
    if (!_splashDone) {
      return SplashScreen(
        onComplete: () {
          if (mounted) setState(() => _splashDone = true);
        },
      );
    }

    final connection = context.watch<ConnectionService>();

    // Route based on connection state machine:
    //   disconnected / failed → ConnectScreen (user must act)
    //   connecting / connected / reconnecting → HomeScreen
    // Key change: reconnecting keeps user on HomeScreen with a
    // banner instead of kicking them back to ConnectScreen.
    final showHome = switch (connection.state) {
      AppConnectionState.disconnected || AppConnectionState.failed => false,
      AppConnectionState.connecting ||
      AppConnectionState.connected ||
      AppConnectionState.reconnecting =>
        true,
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      child: showHome
          ? const HomeScreen(key: ValueKey('home'))
          : const ConnectScreen(key: ValueKey('connect')),
    );
  }
}
