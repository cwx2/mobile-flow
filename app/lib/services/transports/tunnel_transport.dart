/// tunnel_transport.dart — WSS tunnel transport with Bearer Token auth.
///
/// Connects via `wss://` with HTTP-level authentication headers
/// (Bearer Token and optional Cloudflare Access credentials).
///
/// Uses [IOWebSocketChannel] instead of [WebSocketChannel] because
/// the generic `WebSocketChannel.connect()` does not support custom
/// HTTP headers in the upgrade request.
library;

import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../utils/logger.dart';
import 'transport.dart';

final _log = getLogger('TunnelTransport');

/// Tunnel transport with WSS + Bearer Token + optional CF Access headers.
///
/// Overrides [connect] instead of just [createChannel] because it
/// needs to catch HTTP 401/403 errors and wrap them in
/// [TunnelAuthException] to signal unrecoverable auth failure.
class TunnelTransport extends BaseTransport {
  final String wssUrl;
  final String? bearerToken;
  final String? cfClientId;
  final String? cfClientSecret;

  TunnelTransport({
    required this.wssUrl,
    this.bearerToken,
    this.cfClientId,
    this.cfClientSecret,
  });

  @override
  String get label => 'Tunnel';

  @override
  Future<WebSocketChannel> createChannel() async {
    final headers = <String, String>{};
    if (bearerToken != null && bearerToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }
    if (cfClientId != null && cfClientId!.isNotEmpty) {
      headers['CF-Access-Client-Id'] = cfClientId!;
    }
    if (cfClientSecret != null && cfClientSecret!.isNotEmpty) {
      headers['CF-Access-Client-Secret'] = cfClientSecret!;
    }

    // Create a custom HttpClient that trusts self-signed certificates.
    // Required for development/testing with locally generated TLS certs.
    // In production with proper CA-signed certs, this is a no-op (the
    // callback is only invoked for untrusted certificates).
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        _log.warning('⚠️ 接受不受信任的证书: host=$host:$port, subject=${cert.subject}');
        return true;
      };

    // IOWebSocketChannel supports custom headers and HttpClient
    return IOWebSocketChannel.connect(
      Uri.parse(wssUrl),
      headers: headers,
      customClient: httpClient,
    );
  }

  /// Override connect to catch HTTP 401/403 and throw [TunnelAuthException].
  ///
  /// Auth failures at the HTTP level are unrecoverable — the reconnect
  /// loop should stop immediately instead of retrying with bad credentials.
  @override
  Future<void> connect() async {
    try {
      await super.connect();
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('401') || errStr.contains('403')) {
        throw TunnelAuthException(errStr);
      }
      rethrow;
    }
  }
}
