/// lan_transport.dart — LAN direct WebSocket transport.
///
/// Connects to the Agent via `ws://host:port` on the local network.
/// No encryption at the transport level (app-layer encryption is
/// handled by [WebSocketService] after auth.result delivers the secret).
library;

import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport.dart';

/// LAN direct connection transport.
///
/// The simplest transport — just a plain WebSocket to a local IP.
/// All the lifecycle logic (connect, listen, close) is inherited
/// from [BaseTransport]; this class only provides the channel URI.
class LanTransport extends BaseTransport {
  final String host;
  final int port;

  LanTransport({required this.host, required this.port});

  @override
  String get label => 'LAN';

  @override
  Future<WebSocketChannel> createChannel() async {
    return WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
  }
}
