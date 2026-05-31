/// relay_transport.dart — Relay server transport with E2E encryption.
///
/// Connects to a relay server that mediates between App and Agent.
/// All messages are encrypted/decrypted at the transport level using
/// [CryptoModule], so the relay server never sees plaintext.
///
/// Send path: JSON → encrypt → envelope → relay server.
/// Receive path: relay server → envelope → decrypt → JSON.
library;

import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../crypto/crypto_module.dart';
import 'transport.dart';

/// Relay transport with end-to-end encryption.
///
/// Overrides [transformIncoming] and [transformOutgoing] to handle
/// the encryption envelope. The relay server only sees opaque
/// encrypted blobs — it cannot read message content.
class RelayTransport extends BaseTransport {
  final String relayUrl;
  final String deviceId;
  final String targetDeviceId;
  final CryptoModule crypto;

  RelayTransport({
    required this.relayUrl,
    required this.deviceId,
    required this.targetDeviceId,
    required this.crypto,
  });

  @override
  String get label => 'Relay';

  @override
  Future<WebSocketChannel> createChannel() async {
    final uri = Uri.parse('$relayUrl/ws/app/$deviceId?target=$targetDeviceId');
    return WebSocketChannel.connect(uri);
  }

  /// Decrypt incoming relay envelope.
  ///
  /// Relay messages arrive as JSON envelopes with `t: "encrypted"`
  /// and `c: <ciphertext>`. Non-encrypted messages pass through.
  @override
  String transformIncoming(String raw) {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    if (envelope['t'] == 'encrypted') {
      final decrypted = crypto.decrypt(envelope['c'] as String);
      return jsonEncode(decrypted);
    }
    return raw;
  }

  /// Encrypt outgoing message into a relay envelope.
  @override
  String transformOutgoing(String jsonMessage) {
    final message = jsonDecode(jsonMessage) as Map<String, dynamic>;
    final encrypted = crypto.encrypt(message);
    return jsonEncode({
      't': 'encrypted',
      'v': 1,
      'from': deviceId,
      'to': targetDeviceId,
      'c': encrypted,
    });
  }
}
