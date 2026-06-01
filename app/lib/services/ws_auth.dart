/// ws_auth.dart — Authentication flows and reconnection orchestration.
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

/// Authentication flows and reconnection orchestration.
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
    required WebSocketService ws, required ConnectionManager connManager,
    required WsCrypto crypto, required WsHeartbeat heartbeat,
  })  : _ws = ws, _connManager = connManager,
        _crypto = crypto, _heartbeat = heartbeat;

  /// Establish a LAN direct connection and authenticate via pair token.
  Future<bool> connectLan(String host, int port, String pairToken) async {
    _ws.isConnectingFlag = true;
    try {
      _crypto.reset();
      await _connManager.connectLan(host, port, pairToken: pairToken);
      _ws.listenMessages();
      _ws.send(WsMessage(type: MessageType.authPair,
          payload: AuthPairPayload(token: pairToken).toJson()));
      final authResult = await _awaitAuthResult();
      if (authResult.success) {
        _log.info('✅ 连接成功: $host:$port');
        _ws.connection?.setConnection(host: host, port: port);
        await _handleAuthSuccess(authResult, isReconnect: false);
      }
      _ws.isConnectingFlag = false;
      return authResult.success;
    } catch (e) {
      _log.severe('连接失败: $e');
      await _connManager.disconnect();
      _ws.isConnectingFlag = false;
      return false;
    }
  }

  /// Reconnect using a saved session token (skips pairing).
  Future<bool> reconnectWithSession(
      String host, int port, String sessionToken) async {
    _ws.isConnectingFlag = true;
    try {
      await _crypto.restoreSecret();
      await _connManager.connectLan(host, port);
      _ws.listenMessages();
      await _sendAuthConnect(sessionToken);
      final authResult = await _awaitAuthResult();
      if (authResult.success) {
        _log.info('✅ 自动重连成功: $host:$port');
        _ws.connection?.setConnection(host: host, port: port);
        await _handleAuthSuccess(authResult,
            isReconnect: false, fallbackSessionToken: sessionToken);
      } else {
        _log.warning('自动重连失败: ${authResult.error ?? ""}');
        if (authResult.shouldRepair == true) {
          _log.info('Agent 要求重新配对，清除 session_token');
          await _crypto.clearSession();
        }
      }
      _ws.isConnectingFlag = false;
      return authResult.success;
    } catch (e) {
      _log.severe('自动重连异常: $e');
      await _connManager.disconnect();
      _ws.isConnectingFlag = false;
      return false;
    }
  }

  /// Establish a relay connection (remote mode, E2E encrypted).
  Future<bool> connectRelay({
    required String relayUrl, required String deviceId,
    required String targetDeviceId, required CryptoModule crypto,
  }) async {
    _ws.isConnectingFlag = true;
    try {
      await _connManager.connectRelay(relayUrl: relayUrl, deviceId: deviceId,
          targetDeviceId: targetDeviceId, crypto: crypto);
      if (!_connManager.isConnected) {
        _ws.isConnectingFlag = false;
        return false;
      }
      _ws.listenMessages();
      _ws.connection?.setConnection(host: relayUrl, port: 0);
      _ws.connection?.markConnected('relay:$targetDeviceId');
      _ws.cliOps.requestCLIList();
      _ws.projectOps.requestCurrentProject();
      _heartbeat.start();
      _ws.isConnectingFlag = false;
      return true;
    } catch (e) {
      _log.severe('Relay 连接失败: $e');
      _ws.isConnectingFlag = false;
      return false;
    }
  }

  /// Establish a tunnel connection (wss:// + Bearer Token).
  Future<bool> connectTunnel({
    required String wssUrl, String? bearerToken,
    String? cfClientId, String? cfClientSecret, String pairToken = '',
  }) async {
    _ws.isConnectingFlag = true;
    try {
      // Tunnel uses TLS for encryption — disable LAN-level NaCl encryption
      _crypto.reset();
      await _connManager.connectTunnel(wssUrl: wssUrl, bearerToken: bearerToken,
          cfClientId: cfClientId, cfClientSecret: cfClientSecret);
      _ws.listenMessages();
      if (pairToken.isNotEmpty) {
        _ws.send(WsMessage(type: MessageType.authPair,
            payload: AuthPairPayload(token: pairToken).toJson()));
        if (!(await _awaitAuthResult()).success) {
          _ws.isConnectingFlag = false;
          return false;
        }
      }
      _ws.connection?.setConnection(host: wssUrl, port: 0);
      _ws.connection?.markConnected('tunnel');
      _ws.cliOps.requestCLIList();
      _ws.projectOps.requestCurrentProject();
      _heartbeat.start();
      _ws.isConnectingFlag = false;
      return true;
    } catch (e) {
      _log.severe('Tunnel 连接失败: $e');
      _ws.isConnectingFlag = false;
      return false;
    }
  }

  Future<AuthResultPayload> _awaitAuthResult() async {
    final msg = await _ws.messageStream
        .where((m) => m.type == MessageType.authResult)
        .first.timeout(const Duration(seconds: 5));
    return AuthResultPayload.fromJson(msg.payload);
  }

  Future<void> _sendAuthConnect(String sessionToken) async {
    final cid = await _crypto.savedClientId;
    _ws.send(WsMessage(type: MessageType.authConnect,
        payload: AuthConnectPayload(sessionToken: sessionToken,
            clientId: (cid != null && cid.isNotEmpty) ? cid : null).toJson()));
  }

  /// Consolidates the three duplicated scope-resume code paths.
  Future<void> _handleAuthSuccess(AuthResultPayload result, {
    required bool isReconnect, String? fallbackSessionToken,
  }) async {
    _crypto.initFromAuthResult(result);
    final token = result.sessionToken ?? fallbackSessionToken ?? '';
    _ws.connection?.markConnected(token);
    await _crypto.persistCredentials(token, result.secret, clientId: result.clientId);
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
    _ws.cliOps.requestCLIList();
    _ws.projectOps.requestCurrentProject();
    _heartbeat.start();
  }

  // ── Reconnect ──

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
          await _connManager.reconnect();
          _ws.listenMessages();
          final sessionToken = _ws.connection?.sessionToken;
          if (sessionToken != null && sessionToken.isNotEmpty) {
            await _crypto.restoreSecret();
            await _sendAuthConnect(sessionToken);
            final msg = await _ws.messageStream
                .where((m) => m.type == MessageType.authResult)
                .first.timeout(kAuthTimeout);
            final authResult = AuthResultPayload.fromJson(msg.payload);
            if (authResult.success) {
              _log.info('✅ 重连成功 (第 $attempt 次)');
              _isReconnecting = false;
              await _handleAuthSuccess(authResult,
                  isReconnect: true, fallbackSessionToken: sessionToken);
              _ws.notifyUI();
              return;
            }
            _log.warning('⚠️ 重连认证失败: ${authResult.error ?? "unknown"}');
            await _connManager.disconnect();
          } else {
            _log.warning('⚠️ 无 session_token，无法重连认证');
          }
        } on TunnelAuthException {
          _log.severe('❌ Tunnel 认证失败，停止重连');
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

  /// Cancel any in-progress reconnect loop.
  void cancelReconnect() {
    _reconnectTimer?.cancel(); _reconnectTimer = null; _isReconnecting = false;
  }

  /// Record the timestamp when the app enters background.
  void onAppBackgrounded() { _backgroundedAt ??= DateTime.now(); }

  /// Check connection health when the app returns to foreground.
  void handleAppResumed() {
    final s = _ws.connection?.state;
    if (s == null || s == AppConnectionState.disconnected ||
        s == AppConnectionState.failed || _isReconnecting) {
      _backgroundedAt = null;
      return;
    }
    final bgSec = _backgroundedAt != null
        ? DateTime.now().difference(_backgroundedAt!).inSeconds : 0;
    _backgroundedAt = null;
    if (s == AppConnectionState.connected) {
      _log.fine('后台时间 ${bgSec}s，重启心跳探测');
      _heartbeat.start();
    }
  }
}
