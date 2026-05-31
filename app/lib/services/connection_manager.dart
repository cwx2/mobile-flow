/// connection_manager.dart — Unified transport manager.
///
/// [ConnectionManager] is the single entry point for [WebSocketService]
/// to establish, send, receive, and reconnect connections. It delegates
/// to the appropriate [Transport] implementation (LAN, Relay, Tunnel)
/// while hiding the transport details from the upper layer.
///
/// Stores connection parameters so the reconnect loop can create
/// fresh Transport instances without remembering the original args.
library;

import '../crypto/crypto_module.dart';
import '../utils/logger.dart';
import 'transports/transport.dart';
import 'transports/lan_transport.dart';
import 'transports/relay_transport.dart';
import 'transports/tunnel_transport.dart';

// Re-export Transport types so existing imports keep working.
// Files that `import 'connection_manager.dart'` get Transport,
// TunnelAuthException, and ConnectionMode without extra imports.
export 'transports/transport.dart' show Transport, TunnelAuthException;

final _log = getLogger('ConnManager');

/// Connection mode enumeration.
enum ConnectionMode {
  /// LAN direct connection (ws://IP:Port).
  lan,

  /// Relay server mediated connection (wss:// + E2E encryption).
  relay,

  /// Tunnel direct connection (wss:// + Bearer Token).
  tunnel,
}

/// Unified connection manager entry point.
///
/// [WebSocketService] uses this to send/receive messages without
/// caring about the underlying transport mode (LAN, Relay, or Tunnel).
///
/// Stores connection parameters so the reconnect loop can create
/// fresh Transport instances without needing the original connect args.
class ConnectionManager {
  Transport? _transport;
  ConnectionMode _mode = ConnectionMode.lan;

  // Saved connection parameters for reconnect
  String? _lanHost;
  int _lanPort = 9600;
  String? _relayUrl;
  String? _relayDeviceId;
  String? _relayTargetDeviceId;
  CryptoModule? _relayCrypto;
  String? _tunnelWssUrl;
  String? _tunnelBearerToken;
  String? _tunnelCfClientId;
  String? _tunnelCfClientSecret;

  ConnectionMode get mode => _mode;
  bool get isConnected => _transport?.isConnected ?? false;
  Stream<String>? get messageStream => _transport?.messageStream;

  /// Establish a LAN direct connection.
  Future<void> connectLan(String host, int port, {String pairToken = '000000'}) async {
    await _transport?.close();
    _mode = ConnectionMode.lan;
    _lanHost = host;
    _lanPort = port;
    _transport = LanTransport(host: host, port: port);
    await _transport!.connect();
  }

  /// Establish a relay connection with E2E encryption.
  Future<void> connectRelay({
    required String relayUrl,
    required String deviceId,
    required String targetDeviceId,
    required CryptoModule crypto,
  }) async {
    await _transport?.close();
    _mode = ConnectionMode.relay;
    _relayUrl = relayUrl;
    _relayDeviceId = deviceId;
    _relayTargetDeviceId = targetDeviceId;
    _relayCrypto = crypto;
    _transport = RelayTransport(
      relayUrl: relayUrl,
      deviceId: deviceId,
      targetDeviceId: targetDeviceId,
      crypto: crypto,
    );
    await _transport!.connect();
  }

  /// Establish a tunnel connection via WSS.
  Future<void> connectTunnel({
    required String wssUrl,
    String? bearerToken,
    String? cfClientId,
    String? cfClientSecret,
  }) async {
    await _transport?.close();
    _mode = ConnectionMode.tunnel;
    _tunnelWssUrl = wssUrl;
    _tunnelBearerToken = bearerToken;
    _tunnelCfClientId = cfClientId;
    _tunnelCfClientSecret = cfClientSecret;
    _transport = TunnelTransport(
      wssUrl: wssUrl,
      bearerToken: bearerToken,
      cfClientId: cfClientId,
      cfClientSecret: cfClientSecret,
    );
    await _transport!.connect();
  }

  /// Create a fresh transport and connect using saved parameters.
  ///
  /// Called by the reconnect loop in [WebSocketService]. Creates a
  /// new Transport instance (the old one is dead) and attempts a
  /// single TCP connection. Throws on failure — the caller handles
  /// retry logic.
  Future<void> reconnect() async {
    _log.fine('reconnect: 开始, mode=$_mode, 旧transport=${_transport != null}');
    _log.fine('reconnect: 丢弃旧 transport (非优雅关闭)...');
    // Non-graceful close: skip sink.close() to avoid hanging on dead channel
    await _transport?.close(graceful: false);
    _log.fine('reconnect: 旧 transport 已丢弃, 创建新 transport...');
    switch (_mode) {
      case ConnectionMode.lan:
        if (_lanHost == null) {
          throw StateError('No saved LAN connection parameters');
        }
        _transport = LanTransport(host: _lanHost!, port: _lanPort);
        await _transport!.connect();
      case ConnectionMode.relay:
        if (_relayUrl == null || _relayDeviceId == null ||
            _relayTargetDeviceId == null || _relayCrypto == null) {
          throw StateError('No saved Relay connection parameters');
        }
        _transport = RelayTransport(
          relayUrl: _relayUrl!,
          deviceId: _relayDeviceId!,
          targetDeviceId: _relayTargetDeviceId!,
          crypto: _relayCrypto!,
        );
        await _transport!.connect();
      case ConnectionMode.tunnel:
        if (_tunnelWssUrl == null) {
          throw StateError('No saved Tunnel connection parameters');
        }
        _transport = TunnelTransport(
          wssUrl: _tunnelWssUrl!,
          bearerToken: _tunnelBearerToken,
          cfClientId: _tunnelCfClientId,
          cfClientSecret: _tunnelCfClientSecret,
        );
        await _transport!.connect();
    }
  }

  /// Send a JSON message string through the active transport.
  void send(String jsonMessage) => _transport?.send(jsonMessage);

  /// Disconnect and release the active transport.
  Future<void> disconnect() async {
    await _transport?.close();
    _transport = null;
  }
}
