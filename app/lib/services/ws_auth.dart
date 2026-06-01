/// ws_auth.dart — Unified authentication and reconnection orchestration.
///
/// Provides a single [connect] entry point for all connection modes (LAN,
/// Tunnel, Relay). The auth handshake is mode-specific but the post-connect
/// flow (heartbeat, CLI init, project sync) is shared across all modes.
///
/// Reconnection is also unified: all modes support automatic reconnect
/// with exponential backoff. The reconnect strategy differs by mode:
///   - LAN: send auth.connect with saved session_token
///   - Tunnel: re-establish TLS + Bearer Token (no auth handshake needed)
///   - Relay: re-connect to relay server with saved crypto (no auth needed)
library;

import 'dart:async';
import 'dart:math';
import '../core/connection_config.dart';
import '../crypto/crypto_module.dart';
import '../models/protocol.dart';
import '../models/payloads/auth_payloads.g.dart';
import '../models/payloads/cli_payloads.g.dart';
import '../utils/logger.dart';
import 'connection_manager.dart';
import 'connection_service.dart';
import 'ws_crypto.dart';
import 'ws_heartbeat.dart';
import 'websocket_service.dart';

final _log = getLogger('WsAuth');

/// Unified authentication and reconnection orchestration.
///
/// All connection modes flow through the same pipeline:
///   1. Reset encryption state
///   2. Establish transport (mode-specific)
///   3. Auth handshake (LAN only; Tunnel/Relay skip)
///   4. Post-connect setup (shared: heartbeat, CLI list, project sync)
///
/// Reconnection follows the same pattern but uses saved credentials
/// instead of user-provided ones.
class WsAuth {
  final WebSocketService _ws;
  final ConnectionManager _connManager;
  final WsCrypto _crypto;
  final WsHeartbeat _heartbeat;
  bool _isReconnecting = false;
  Timer? _reconnectTimer;
  DateTime? _backgroundedAt;
  bool get isReconnecting => _isReconnecting;

  WsAuth({
    required WebSocketService ws,
    required ConnectionManager connManager,
    required WsCrypto crypto,
    required WsHeartbeat heartbeat,
  })  : _ws = ws,
        _connManager = connManager,
        _crypto = crypto,
        _heartbeat = heartbeat;

  // ═══════════════════════════════════════════════════════════════════
  // Public API — unified connect entry points
  // ═══════════════════════════════════════════════════════════════════

  /// Establish a LAN direct connection and authenticate via pair token.
  ///
  /// Flow: transport connect → auth.pair → auth.result → post-connect.
  Future<bool> connectLan(String host, int port, String pairToken) async {
    return _connect(
      mode: ConnectionMode.lan,
      setupTransport: () => _connManager.connectLan(host, port, pairToken: pairToken),
      setConnectionInfo: () => _ws.connection?.setConnection(host: host, port: port),
      authStrategy: () => _authWithPairToken(pairToken),
    );
  }

  /// Reconnect using a saved session token (skips pairing).
  ///
  /// Flow: transport connect → auth.connect → auth.result → post-connect.
  Future<bool> reconnectWithSession(
      String host, int port, String sessionToken) async {
    return _connect(
      mode: ConnectionMode.lan,
      setupTransport: () async {
        await _crypto.restoreSecret();
        await _connManager.connectLan(host, port);
      },
      setConnectionInfo: () => _ws.connection?.setConnection(host: host, port: port),
      authStrategy: () => _authWithSessionToken(sessionToken),
    );
  }

  /// Establish a relay connection (remote mode, E2E encrypted).
  ///
  /// Flow: transport connect → (no auth) → post-connect.
  /// Encryption is handled at the transport layer by RelayTransport.
  Future<bool> connectRelay({
    required String relayUrl,
    required String deviceId,
    required String targetDeviceId,
    required CryptoModule crypto,
  }) async {
    return _connect(
      mode: ConnectionMode.relay,
      setupTransport: () => _connManager.connectRelay(
        relayUrl: relayUrl,
        deviceId: deviceId,
        targetDeviceId: targetDeviceId,
        crypto: crypto,
      ),
      setConnectionInfo: () => _ws.connection?.setConnection(
        host: relayUrl, port: 0, mode: ConnectionMode.relay,
      ),
      authStrategy: null, // Relay: no auth handshake needed
    );
  }

  /// Establish a tunnel connection (wss:// + Bearer Token).
  ///
  /// Flow: transport connect → (no auth) → post-connect.
  /// Authentication is at the HTTP level (Bearer Token in headers).
  /// TLS provides encryption — no app-layer crypto needed.
  Future<bool> connectTunnel({
    required String wssUrl,
    String? bearerToken,
    String? cfClientId,
    String? cfClientSecret,
  }) async {
    return _connect(
      mode: ConnectionMode.tunnel,
      setupTransport: () => _connManager.connectTunnel(
        wssUrl: wssUrl,
        bearerToken: bearerToken,
        cfClientId: cfClientId,
        cfClientSecret: cfClientSecret,
      ),
      setConnectionInfo: () => _ws.connection?.setConnection(
        host: wssUrl, port: 0, mode: ConnectionMode.tunnel,
      ),
      authStrategy: null, // Tunnel: Bearer Token validated at HTTP level
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Unified connect pipeline
  // ═══════════════════════════════════════════════════════════════════

  /// Core connect pipeline shared by all modes.
  ///
  /// Phases:
  ///   1. Reset state (crypto, flags)
  ///   2. Establish transport via [setupTransport]
  ///   3. Start listening to message stream
  ///   4. Run auth strategy (if provided; null = skip auth)
  ///   5. Post-connect: set connection info, start heartbeat, request data
  ///
  /// Returns true on success, false on auth failure or transport error.
  Future<bool> _connect({
    required ConnectionMode mode,
    required Future<void> Function() setupTransport,
    required void Function() setConnectionInfo,
    required Future<bool> Function()? authStrategy,
  }) async {
    _ws.isConnectingFlag = true;
    try {
      // Phase 1: Reset encryption state — prevents stale LAN keys from
      // being used on Tunnel/Relay, or old keys from a previous session.
      _crypto.reset();

      // Phase 2: Establish transport connection
      await setupTransport();
      if (!_connManager.isConnected) {
        _ws.isConnectingFlag = false;
        return false;
      }

      // Phase 3: Subscribe to incoming messages
      _ws.listenMessages();

      // Phase 4: Auth handshake (mode-specific)
      if (authStrategy != null) {
        final success = await authStrategy();
        if (!success) {
          _ws.isConnectingFlag = false;
          return false;
        }
      } else {
        // No auth needed — directly mark connected
        setConnectionInfo();
        _ws.connection?.markConnected(mode.name);
      }

      // Phase 5: Post-connect (shared across all modes)
      _postConnect();
      _ws.isConnectingFlag = false;
      return true;
    } catch (e) {
      _log.severe('连接失败 (mode=$mode): $e');
      await _connManager.disconnect();
      _ws.isConnectingFlag = false;
      return false;
    }
  }

  /// Shared post-connect actions for all modes.
  ///
  /// Requests initial data from Agent and starts the heartbeat cycle.
  void _postConnect() {
    _ws.cliOps.requestCLIList();
    _ws.projectOps.requestCurrentProject();
    _heartbeat.start();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Auth strategies
  // ═══════════════════════════════════════════════════════════════════

  /// LAN auth: send auth.pair with password, await auth.result.
  ///
  /// On success, initializes encryption and persists session credentials.
  Future<bool> _authWithPairToken(String pairToken) async {
    _ws.send(WsMessage(
      type: MessageType.authPair,
      payload: AuthPairPayload(token: pairToken).toJson(),
    ));
    final authResult = await _awaitAuthResult();
    if (authResult.success) {
      _log.info('✅ 配对认证成功');
      await _handleAuthSuccess(authResult, isReconnect: false);
    }
    return authResult.success;
  }

  /// LAN reconnect auth: send auth.connect with session token, await result.
  ///
  /// On success, restores encryption and resumes session scope.
  Future<bool> _authWithSessionToken(String sessionToken) async {
    await _sendAuthConnect(sessionToken);
    final authResult = await _awaitAuthResult();
    if (authResult.success) {
      _log.info('✅ Session 认证成功');
      await _handleAuthSuccess(
        authResult,
        isReconnect: false,
        fallbackSessionToken: sessionToken,
      );
    } else {
      _log.warning('Session 认证失败: ${authResult.error ?? ""}');
      if (authResult.shouldRepair == true) {
        _log.info('Agent 要求重新配对，清除 session_token');
        await _crypto.clearSession();
      }
    }
    return authResult.success;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Auth helpers
  // ═══════════════════════════════════════════════════════════════════

  Future<AuthResultPayload> _awaitAuthResult() async {
    final msg = await _ws.messageStream
        .where((m) => m.type == MessageType.authResult)
        .first
        .timeout(const Duration(seconds: 5));
    return AuthResultPayload.fromJson(msg.payload);
  }

  Future<void> _sendAuthConnect(String sessionToken) async {
    final cid = await _crypto.savedClientId;
    _ws.send(WsMessage(
      type: MessageType.authConnect,
      payload: AuthConnectPayload(
        sessionToken: sessionToken,
        clientId: (cid != null && cid.isNotEmpty) ? cid : null,
      ).toJson(),
    ));
  }

  /// Process a successful auth.result: init crypto, persist credentials,
  /// handle scope resume, and set connection state.
  Future<void> _handleAuthSuccess(
    AuthResultPayload result, {
    required bool isReconnect,
    String? fallbackSessionToken,
  }) async {
    // Initialize LAN encryption from the secret in auth.result
    _crypto.initFromAuthResult(result);
    final token = result.sessionToken ?? fallbackSessionToken ?? '';
    // Update connection info (host/port already set by setConnectionInfo)
    _ws.connection?.markConnected(token);
    await _crypto.persistCredentials(token, result.secret,
        clientId: result.clientId);

    // Handle scope resume (Agent kept ACP alive during disconnect)
    final wasResumed = result.resumed == true;
    if (wasResumed) {
      final cliName = result.cliName ?? '';
      if (cliName.isNotEmpty) _ws.defaultCli = cliName;
      if ((result.cliState ?? '') == 'ready') {
        _ws.handleCliStatus(CliStatusPayload(
            cli: cliName, state: 'ready', message: 'AI Agent 已就绪'));
        _ws.historyRequestedForCli = true;
        _ws.chatOps.requestChatHistory();
      }
      _log.info('♻️ Scope 恢复，跳过 CLI 初始化');
    } else if (isReconnect) {
      _ws.resetCliState();
      _ws.historyRequestedForCli = false;
    } else {
      _ws.historyRequestedForCli = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Reconnect — unified for all modes
  // ═══════════════════════════════════════════════════════════════════

  /// Begin automatic reconnection with exponential backoff.
  ///
  /// Works for all modes: LAN re-authenticates with session token,
  /// Tunnel/Relay simply re-establish the transport (auth is implicit).
  void beginReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    _ws.connection?.markReconnecting(maxAttempts: kReconnectMaxAttempts);
    _ws.notifyUI();
    _startReconnectLoop();
  }

  void _startReconnectLoop() {
    int attempt = 0;
    final random = Random();

    void tryReconnect() {
      if (_ws.connection?.state != AppConnectionState.reconnecting) {
        _isReconnecting = false;
        return;
      }
      attempt++;
      _ws.connection?.updateReconnectAttempt(attempt);
      if (attempt > kReconnectMaxAttempts) {
        _log.severe('❌ 重连耗尽: $kReconnectMaxAttempts 次');
        _isReconnecting = false;
        _ws.connection?.markFailed();
        _ws.notifyUI();
        return;
      }

      final baseMs = kReconnectBaseDelay.inMilliseconds;
      final maxMs = kReconnectMaxDelay.inMilliseconds;
      final jMs = kReconnectJitter.inMilliseconds;
      final expMs = (baseMs * (1 << (attempt - 1))).clamp(0, maxMs);
      final delayMs = (expMs + random.nextInt(jMs * 2) - jMs).clamp(0, maxMs);
      _log.warning('🔄 重连 #$attempt/$kReconnectMaxAttempts, ${delayMs}ms 后...');

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
        if (_ws.connection?.state != AppConnectionState.reconnecting) {
          _isReconnecting = false;
          return;
        }
        try {
          final success = await _performReconnect();
          if (success) {
            _log.info('✅ 重连成功 (第 $attempt 次)');
            _isReconnecting = false;
            _ws.notifyUI();
            return;
          }
        } on TunnelAuthException {
          _log.severe('❌ Tunnel 认证失败（Bearer Token 无效），停止重连');
          _isReconnecting = false;
          _ws.connection?.markFailed();
          _ws.notifyUI();
          return;
        } catch (e) {
          _log.warning('⚠️ 重连尝试 #$attempt 失败: $e');
        }
        tryReconnect();
      });
    }

    tryReconnect();
  }

  /// Execute a single reconnect attempt based on current mode.
  ///
  /// LAN: reconnect transport + auth.connect with session token.
  /// Tunnel: reconnect transport (Bearer Token in headers = implicit auth).
  /// Relay: reconnect transport (crypto in transport = implicit auth).
  Future<bool> _performReconnect() async {
    // Phase 1: Re-establish transport using saved parameters
    await _connManager.reconnect();
    _ws.listenMessages();

    // Phase 2: Mode-specific re-authentication
    final mode = _connManager.mode;
    switch (mode) {
      case ConnectionMode.lan:
        // LAN requires explicit re-auth with session token
        final sessionToken = _ws.connection?.sessionToken;
        if (sessionToken == null || sessionToken.isEmpty) {
          _log.warning('⚠️ 无 session_token，无法重连认证');
          await _connManager.disconnect();
          return false;
        }
        _crypto.reset(); // Clear stale key before restoring from storage
        await _crypto.restoreSecret();
        await _sendAuthConnect(sessionToken);
        final authResult = await _ws.messageStream
            .where((m) => m.type == MessageType.authResult)
            .first
            .timeout(kAuthTimeout);
        final result = AuthResultPayload.fromJson(authResult.payload);
        if (!result.success) {
          _log.warning('⚠️ 重连认证失败: ${result.error ?? "unknown"}');
          await _connManager.disconnect();
          return false;
        }
        await _handleAuthSuccess(result,
            isReconnect: true, fallbackSessionToken: sessionToken);
        return true;

      case ConnectionMode.tunnel:
      case ConnectionMode.relay:
        // Tunnel/Relay: transport reconnect is sufficient (auth is implicit).
        // Bearer Token is in headers (Tunnel), crypto is in transport (Relay).
        _ws.connection?.markConnected(mode.name);
        _postConnect();
        return true;
    }
  }

  /// Cancel any in-progress reconnect loop.
  void cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
  }

  // ═══════════════════════════════════════════════════════════════════
  // App lifecycle
  // ═══════════════════════════════════════════════════════════════════

  /// Record the timestamp when the app enters background.
  void onAppBackgrounded() {
    _backgroundedAt ??= DateTime.now();
  }

  /// Check connection health when the app returns to foreground.
  void handleAppResumed() {
    final s = _ws.connection?.state;
    if (s == null ||
        s == AppConnectionState.disconnected ||
        s == AppConnectionState.failed ||
        _isReconnecting) {
      _backgroundedAt = null;
      return;
    }
    final bgSec = _backgroundedAt != null
        ? DateTime.now().difference(_backgroundedAt!).inSeconds
        : 0;
    _backgroundedAt = null;
    if (s == AppConnectionState.connected) {
      _log.fine('后台时间 ${bgSec}s，重启心跳探测');
      _heartbeat.start();
    }
  }
}
