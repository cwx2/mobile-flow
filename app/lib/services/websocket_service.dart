/// websocket_service.dart — WebSocket communication service (thin layer).
///
/// Manages the WebSocket connection to the desktop agent, handles
/// message send/receive, and routes incoming messages to [ChatStateMixin]
/// and [AppEventBus].
///
/// Uses mixin instead of multiple Providers because Flutter's
/// `context.watch` works most efficiently with a single ChangeNotifier.
/// Message routing goes two ways: direct state update (mixin) +
/// emit to EventBus (for other modules to listen).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../models/protocol.dart';
import '../models/context_reference.dart';
import '../utils/logger.dart';
import '../core/event_bus.dart';
import 'chat_state.dart';
import 'connection_service.dart';
import 'connection_manager.dart';
import '../widgets/slash_command_menu.dart';
import 'ws_message_sender.dart';
import 'ws_heartbeat.dart';
import 'ws_crypto.dart';
import 'ws_auth.dart';
import 'ws_operations/chat_operations.dart';
import 'ws_operations/file_operations.dart';
import 'ws_operations/git_operations.dart';
import 'ws_operations/cli_operations.dart';
import 'ws_operations/project_operations.dart';
import 'ws_operations/terminal_operations.dart';
import 'ws_operations/plugin_operations.dart';
import 'ws_operations/permission_operations.dart';
import 'ws_operations/test_panel_operations.dart';
import 'ws_operations/run_config_operations.dart';

import '../crypto/crypto_module.dart';
import 'message_handlers/handler_registry.dart';
import 'message_handlers/chat_handler.dart';
import 'message_handlers/cli_handler.dart';
import 'message_handlers/file_handler.dart';
import 'message_handlers/git_handler.dart';
import 'message_handlers/project_handler.dart';
import 'message_handlers/permission_handler.dart';
import 'message_handlers/terminal_handler.dart';
import 'message_handlers/session_handler.dart';
import 'message_handlers/plugin_handler.dart';
import 'message_handlers/state_push_handler.dart';
import 'message_handlers/test_panel_handler.dart';

// Re-export for consumers that import from this file
export 'chat_state.dart' show AgentStatus, CliLifecycleState;

final _log = getLogger('WebSocket');

/// Central WebSocket service managing agent communication.
///
/// Combines connection management, message routing, and chat state
/// (via [ChatStateMixin]) into a single [ChangeNotifier] that screens
/// can watch. Supports LAN, Relay, and Tunnel connection modes
/// transparently through [ConnectionManager].
class WebSocketService extends ChangeNotifier with ChatStateMixin, WidgetsBindingObserver implements MessageSender {
  /// Connection manager (replaces raw WebSocketChannel; supports LAN/Relay/Tunnel)
  final ConnectionManager _connManager = ConnectionManager();

  /// Expose the connection manager for disconnect operations.
  ConnectionManager get connectionManager => _connManager;
  StreamSubscription<String>? _messageSub;
  ConnectionService? _connection;
  AppEventBus? _eventBus;

  // ── LAN encryption (delegated to WsCrypto) ──
  late final WsCrypto _wsCrypto = WsCrypto();

  // ── Heartbeat (delegated to WsHeartbeat) ──
  late final WsHeartbeat _heartbeat = WsHeartbeat(
    sender: this,
    connManager: _connManager,
    onConnectionDead: () => _auth.beginReconnect(),
    onStateChanged: notifyListeners,
  );

  // ── Auth and reconnect (delegated to WsAuth) ──
  late final WsAuth _auth = WsAuth(
    ws: this,
    connManager: _connManager,
    crypto: _wsCrypto,
    heartbeat: _heartbeat,
  );

  // ── Message handler registry (strategy pattern) ──
  late final HandlerRegistry _handlers = _initHandlers();

  // ── Operations layer (domain-specific send methods) ──
  late final ChatOperations chatOps = ChatOperations(this);
  late final FileOperations fileOps = FileOperations(this);
  late final GitOperations gitOps = GitOperations(this);
  late final CliOperations cliOps = CliOperations(this);
  late final ProjectOperations projectOps = ProjectOperations(this);
  late final TerminalOperations terminalOps = TerminalOperations(this);
  late final PluginOperations pluginOps = PluginOperations(this);
  late final PermissionOperations permissionOps = PermissionOperations(this);
  late final TestPanelOperations testPanelOps = TestPanelOperations(this);
  late final RunConfigOperations runConfigOps = RunConfigOperations(this);

  /// Build and populate the handler registry with all message handlers.
  HandlerRegistry _initHandlers() {
    final registry = HandlerRegistry();
    final chat = ChatHandler();
    final cli = CliHandler();
    final file = FileHandler();
    final git = GitHandler();
    final project = ProjectHandler();
    final permission = PermissionHandler();
    final terminal = TerminalHandler();
    final session = SessionHandler();
    final plugin = PluginHandler();
    final statePush = StatePushHandler();
    final testPanel = TestPanelMessageHandler();

    registry.registerAll({
      // Chat
      MessageType.chatStream: chat,
      MessageType.chatDone: chat,
      MessageType.chatError: chat,
      MessageType.chatHistoryResult: chat,
      MessageType.chatHistoryMoreResult: chat,
      MessageType.chatReplayResult: chat,
      // CLI
      MessageType.cliStatus: cli,
      MessageType.cliListResult: cli,
      MessageType.cliCommands: cli,
      // File
      MessageType.fileTreeResult: file,
      MessageType.fileChanged: file,
      // Git (forwarded via messageStream, handler is a no-op)
      MessageType.gitStatusResult: git,
      MessageType.gitLogResult: git,
      MessageType.gitLogSearchResult: git,
      MessageType.gitLogAuthorsResult: git,
      MessageType.gitBranchesResult: git,
      MessageType.gitShowResult: git,
      MessageType.gitDiffResult: git,
      MessageType.gitDiffCommitResult: git,
      MessageType.gitReposResult: git,
      MessageType.gitPushResult: git,
      MessageType.gitPullResult: git,
      MessageType.gitCommitResult: git,
      MessageType.gitExecResult: git,
      // Project
      MessageType.projectCurrent: project,
      // Permission
      MessageType.permissionRequest: permission,
      // Terminal
      MessageType.terminalOutput: terminal,
      // Session
      MessageType.sessionListResult: session,
      // Plugin
      MessageType.pluginListResult: plugin,
      MessageType.pluginConfigGetResult: plugin,
      // State push
      MessageType.statePush: statePush,
      // Test Panel (script execution, preview, API, screenshot, visual diff)
      MessageType.scriptOutput: testPanel,
      MessageType.scriptDone: testPanel,
      MessageType.previewReady: testPanel,
      MessageType.previewOutput: testPanel,
      MessageType.previewStopped: testPanel,
      MessageType.previewFileChanged: testPanel,
      MessageType.previewDetectResult: testPanel,
      MessageType.apiResponse: testPanel,
      MessageType.apiError: testPanel,
      MessageType.screenshotResult: testPanel,
      MessageType.screenshotError: testPanel,
      MessageType.visualDiffResult: testPanel,
      MessageType.runtimeResolveResult: testPanel,
    });
    return registry;
  }

  /// Last measured round-trip latency in milliseconds, or -1 if unknown.
  int get latencyMs => _heartbeat.latencyMs;

  /// Whether the last ping timed out (no pong received within timeout).
  bool get isPingTimedOut => _heartbeat.isPingTimedOut;

  /// Incremented each time a pong is received. UI widgets can listen
  /// to this to trigger a heartbeat pulse animation without polling.
  ValueNotifier<int> get pongNotifier => _heartbeat.pongNotifier;

  /// How long the current connection has been active, or null if not connected.
  Duration? get uptime => _heartbeat.uptime;

  // ── Public accessors for WsAuth ──
  // WsAuth is an internal component that needs deep access to
  // WebSocketService state. These accessors avoid exposing private
  // fields while keeping the coupling explicit.

  /// The connection state machine, accessible to WsAuth for state transitions.
  ConnectionService? get connection => _connection;

  /// Whether a connection attempt is in progress (drives UI spinner).
  set isConnectingFlag(bool v) {
    _isConnecting = v;
    notifyListeners();
  }

  /// Whether chat.history has been requested for the current CLI.
  bool get historyRequestedForCli => _historyRequestedForCli;
  set historyRequestedForCli(bool v) => _historyRequestedForCli = v;

  /// Whether a reconnect loop is currently in progress.
  bool get isReconnecting => _auth.isReconnecting;

  /// Trigger a UI rebuild notification.
  ///
  /// Called by internal components (WsAuth, handlers) that need to notify
  /// listeners but cannot access the protected [notifyListeners].
  // ignore: invalid_use_of_protected_member
  void notifyUI() => notifyListeners();

  // ── Public accessors for message handlers ──

  /// The event bus, accessible to handlers for emitting events.
  AppEventBus? get eventBus => _eventBus;

  /// The message stream controller, accessible to handlers that need
  /// to inject synthetic messages (e.g. StatePushHandler).
  StreamController<WsMessage> get messageController => _messageController;

  /// The permission stream controller, accessible to PermissionHandler.
  StreamController<Map<String, dynamic>> get permissionController =>
      _permissionController;

  /// Direct access to CLI capabilities map for handler updates.
  Map<String, CliCapabilities> get cliCapabilitiesMap => _cliCapabilities;

  /// Set the current session mode (used by ChatHandler for mode_change chunks).
  set currentModeValue(String v) => _currentMode = v;

  /// Set the ACP config options (used by ChatHandler for config_update chunks).
  set configOptionsValue(List<ConfigOption> v) => _configOptions = v;

  /// Update session info from ACP session_info_update notification.
  ///
  /// Called by ChatHandler when a session_info chunk arrives during streaming.
  /// Updates session title and context usage percentage for UI display.
  void updateSessionInfo(Map<String, dynamic> info) {
    final title = info['title'] as String? ?? '';
    if (title.isNotEmpty) _sessionTitle = title;
    final usage = info['context_usage'];
    if (usage is num) _contextUsage = usage.toDouble();
  }

  /// Set the cached file tree data (used by FileHandler).
  set cachedFileTreeData(List<Map<String, dynamic>>? v) => _cachedFileTree = v;

  /// Set the file tree cache timestamp (used by FileHandler).
  set fileTreeCacheTime(DateTime? v) => _fileTreeCacheTime = v;

  // Current project
  String currentProjectName = '';
  String currentProjectPath = '';

  // Default CLI (fetched from agent, never hardcoded)
  String defaultCli = '';

  // Whether chat.history has been requested for the current CLI after
  // receiving cli.status=ready. Reset on CLI switch or reconnect.
  // Prevents duplicate history requests during the connection lifecycle.
  bool _historyRequestedForCli = false;

  // Installed CLI list (global state shared by chat and terminal)
  List<String> installedClis = [];

  // CLI name → display_name mapping
  Map<String, String> cliDisplayNames = {};

  // CLI capabilities (updated on cli.list.result and cli.status ready)
  final Map<String, CliCapabilities> _cliCapabilities = {};

  /// Get capabilities for the current default CLI.
  CliCapabilities get cliCapabilities =>
      _cliCapabilities[defaultCli] ?? CliCapabilities.empty;

  /// CLI commands for the currently active CLI adapter.
  List<CliCommand> get cliCommands => getCliCommandsFor(defaultCli);

  // Current session mode (updated by ACP current_mode_update)
  String _currentMode = '';
  String get currentMode => _currentMode;

  // ACP config options (updated by ACP config_option_update)
  List<ConfigOption> _configOptions = [];
  List<ConfigOption> get configOptions => _configOptions;

  // ACP session info (updated by ACP session_info_update)
  String _sessionTitle = '';
  String get sessionTitle => _sessionTitle;
  double _contextUsage = 0.0;
  double get contextUsage => _contextUsage;

  // Auto-approve permissions (local setting, not ACP)
  bool autoApprovePermissions = false;

  // Pending permission request
  Map<String, dynamic>? pendingPermission;

  // Pending context references for the next chat message.
  // Populated from ChatInputBar, ContextPicker, or File Browser;
  // cleared after sendChat() includes them in the payload.
  final List<ContextReference> pendingContextReferences = [];

  // ACP terminal output buffer
  final Map<String, List<String>> terminalOutputs = {};

  // Message stream (for UI to listen to specific message types)
  final _messageController = StreamController<WsMessage>.broadcast();
  Stream<WsMessage> get messageStream => _messageController.stream;

  // Cached file tree for autocomplete (avoids re-fetching on every overlay open).
  // Populated when a fileTreeResult arrives, invalidated on file changes.
  List<Map<String, dynamic>>? _cachedFileTree;
  DateTime? _fileTreeCacheTime;
  static const _fileTreeCacheTtl = Duration(minutes: 5);

  /// Get the cached file tree, or null if not loaded/expired.
  ///
  /// Returns the flattened file list if the cache is still within
  /// [_fileTreeCacheTtl], otherwise returns null so callers know
  /// to request a fresh tree from the Agent.
  List<Map<String, dynamic>>? get cachedFileTree {
    if (_cachedFileTree != null && _fileTreeCacheTime != null) {
      if (DateTime.now().difference(_fileTreeCacheTime!) < _fileTreeCacheTtl) {
        return _cachedFileTree;
      }
    }
    return null;
  }

  // Permission request stream
  final _permissionController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get permissionStream =>
      _permissionController.stream;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  /// Inject the [ConnectionService] dependency.
  void updateConnection(ConnectionService connection) {
    if (_connection == null) {
      // First injection — register lifecycle observer once
      WidgetsBinding.instance.addObserver(this);
    }
    _connection = connection;
  }

  /// Inject the [AppEventBus] dependency.
  void updateEventBus(AppEventBus bus) {
    _eventBus = bus;
  }

  /// Get buffered terminal output lines for a given terminal [id].
  List<String> getTerminalOutput(String id) => terminalOutputs[id] ?? [];

  // ── Connection (delegated to WsAuth) ──

  /// Establish a LAN direct connection and authenticate.
  ///
  /// Returns true if auth succeeds within 5 seconds.
  Future<bool> connect(String host, int port, String pairToken) =>
      _auth.connectLan(host, port, pairToken);

  /// Reconnect to a LAN Agent using a saved session token.
  ///
  /// Skips the pairing step — sends auth.connect with the session_token
  /// instead of auth.pair. Returns true if reconnection succeeds.
  Future<bool> reconnectWithSession(String host, int port, String sessionToken) =>
      _auth.reconnectWithSession(host, port, sessionToken);

  /// Establish a relay connection (remote mode, E2E encrypted).
  Future<bool> connectRelay({
    required String relayUrl,
    required String deviceId,
    required String targetDeviceId,
    required CryptoModule crypto,
  }) =>
      _auth.connectRelay(
        relayUrl: relayUrl,
        deviceId: deviceId,
        targetDeviceId: targetDeviceId,
        crypto: crypto,
      );

  /// Establish a tunnel connection (advanced mode, wss:// + Bearer Token).
  Future<bool> connectTunnel({
    required String wssUrl,
    String? bearerToken,
    String? cfClientId,
    String? cfClientSecret,
  }) =>
      _auth.connectTunnel(
        wssUrl: wssUrl,
        bearerToken: bearerToken,
        cfClientId: cfClientId,
        cfClientSecret: cfClientSecret,
      );

  /// Subscribe to the transport's message stream.
  void listenMessages() {
    _messageSub?.cancel();
    _messageSub = _connManager.messageStream?.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
    );
  }

  /// Current connection mode (LAN / Relay / Tunnel).
  ConnectionMode get connectionMode => _connManager.mode;

  // ── Context reference management ──
  // Cross-tab state: references added from File Browser, ContextPicker,
  // or chat bubble taps are stored here and sent with the next message.

  /// Add a context reference to the pending list.
  ///
  /// Called from ChatInputBar, ContextPicker, File Browser, or chat
  /// bubble tap handlers. The reference will be included in the next
  /// `chat.send` payload and cleared after sending.
  void addContextReference(ContextReference ref) {
    pendingContextReferences.add(ref);
    notifyListeners();
  }

  /// Remove a pending context reference by its unique [id].
  ///
  /// Called when the user taps the remove button on a Context_Chip.
  void removeContextReference(String id) {
    pendingContextReferences.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Clear all pending context references.
  ///
  /// Used when the user starts a new session or explicitly clears context.
  void clearContextReferences() {
    pendingContextReferences.clear();
    notifyListeners();
  }

  // ── Public send methods removed ──
  // All domain-specific send methods have been extracted to Operations
  // classes (chatOps, fileOps, gitOps, cliOps, projectOps, terminalOps,
  // pluginOps, permissionOps). Callers use ws.chatOps.sendChat() etc.

  /// Get the display name for a CLI (falls back to raw name).
  String cliDisplayName(String name) => cliDisplayNames[name] ?? name;

  // ── Message receive + routing ──

  /// Serialize and send a [WsMessage] through the connection manager.
  ///
  /// If [WsCrypto] is active (post-pairing LAN mode), encrypts the JSON
  /// payload before sending. Auth messages bypass encryption because
  /// the shared secret is not yet established during pairing.
  @override
  void send(WsMessage msg) {
    final json = jsonEncode(msg.toJson());
    // Pre-pairing auth messages bypass encryption
    if (_wsCrypto.isActive && !_isAuthMessage(msg.type)) {
      try {
        final encrypted = _wsCrypto.encrypt(msg.toJson());
        _connManager.send(encrypted);
        return;
      } catch (e) {
        _log.severe('消息加密失败: $e');
      }
    }
    _connManager.send(json);
  }

  /// Check if a message type is part of the auth handshake.
  ///
  /// Auth messages (pair, connect, result) are always sent in plaintext
  /// because the encryption secret is delivered via auth.result itself.
  bool _isAuthMessage(String type) {
    return type == MessageType.authPair ||
        type == MessageType.authResult ||
        type == MessageType.authConnect;
  }

  /// Parse incoming raw message and route to the appropriate handler.
  ///
  /// If [WsCrypto] is active, attempts to decrypt the raw message first.
  /// Falls back to plaintext parsing for auth messages and pre-pairing state.
  void _onMessage(dynamic raw) {
    try {
      final rawStr = raw as String;
      Map<String, dynamic> parsed;

      // Try decryption if crypto is active
      if (_wsCrypto.isActive) {
        try {
          // Encrypted messages are Base64 strings, not JSON
          // If it starts with '{', it's plaintext (auth message)
          if (!rawStr.startsWith('{')) {
            final decrypted = _wsCrypto.decrypt(rawStr);
            parsed = decrypted;
          } else {
            // Plaintext auth message during transition
            parsed = jsonDecode(rawStr) as Map<String, dynamic>;
          }
        } catch (e) {
          // Decryption failed — try plaintext parse as fallback
          _log.severe('消息解密失败，尝试明文解析: $e');
          try {
            parsed = jsonDecode(rawStr) as Map<String, dynamic>;
          } catch (_) {
            _log.severe('消息解密和明文解析均失败，丢弃消息');
            return; // Drop the message
          }
        }
      } else {
        parsed = jsonDecode(rawStr) as Map<String, dynamic>;
      }

      final msg = WsMessage.fromJson(parsed);
      // Any incoming message proves the connection is alive
      _heartbeat.resetOnActivity();
      _messageController.add(msg);
      _routeMessage(msg);
    } catch (e) {
      _log.severe('解析消息出错: $e');
    }
  }

  /// Route a parsed message to the correct handler based on type.
  void _routeMessage(WsMessage msg) {
    // Suppress verbose logging for high-frequency messages
    if (msg.type != MessageType.chatStream &&
        msg.type != MessageType.fileChanged &&
        msg.type != MessageType.terminalOutput &&
        msg.type != MessageType.statusPong &&
        msg.type != MessageType.statePush &&
        msg.type != MessageType.runConfigOutput) {
      _log.fine('WS msg: ${msg.type}');
    }

    // Pong handled by heartbeat module
    if (msg.type == MessageType.statusPong) {
      _heartbeat.handlePong();
      return;
    }

    // Dispatch to registered handler
    final handler = _handlers.get(msg.type);
    if (handler != null) {
      try {
        handler.handle(msg, this);
      } catch (e) {
        _log.severe('Handler 异常 [${msg.type}]: $e');
      }
    }
    // Messages without handlers are still on messageStream
    // (added in _onMessage before routing)
  }

  void _onError(dynamic error) {
    _log.severe('❌ WebSocket 错误: $error');
    _heartbeat.stop();
    // Tunnel auth failures are unrecoverable — go straight to disconnected
    if (error.toString().contains('tunnel_auth_failed')) {
      _connection?.disconnect();
      notifyListeners();
      return;
    }
    // For all other errors, attempt reconnect if we were connected
    if (_connection?.state == AppConnectionState.connected) {
      _auth.beginReconnect();
    }
  }

  void _onDone() {
    _log.warning('⚠️ WebSocket stream 关闭');
    _heartbeat.stop();
    // Only reconnect if we were in a connected state (not manual disconnect)
    if (_connection?.state == AppConnectionState.connected) {
      _auth.beginReconnect();
    } else if (_connection?.state != AppConnectionState.reconnecting) {
      // Stream closed during connecting or other non-connected state
      _connection?.disconnect();
      notifyListeners();
    }
  }

  // ── App lifecycle (delegated to WsAuth) ──

  /// Handle app foreground/background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _auth.onAppBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      _log.fine('App 回到前台');
      _auth.handleAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat.dispose();
    _auth.cancelReconnect();
    disposeChatState();
    _messageSub?.cancel();
    _connManager.disconnect();
    _messageController.close();
    _permissionController.close();
    super.dispose();
  }
}
