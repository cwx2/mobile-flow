/// qr_parser.dart - Pure Dart utility for parsing mobileflow:// connection URLs.
///
/// Parses QR code payloads into structured connection parameters.
/// No Flutter dependencies — fully unit-testable in isolation.

/// Result of parsing a mobileflow://connect URL.
///
/// Contains the host, port, and token needed to establish a WebSocket
/// connection to the MobileFlow Agent.
class ConnectionParams {
  /// The Agent's IP address or hostname.
  final String host;

  /// The Agent's WebSocket port (1–65535).
  final int port;

  /// The connection/pairing token for authentication.
  final String token;

  const ConnectionParams({
    required this.host,
    required this.port,
    required this.token,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionParams &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          token == other.token;

  @override
  int get hashCode => Object.hash(host, port, token);

  @override
  String toString() => 'ConnectionParams(host: $host, port: $port, token: ***)';
}

/// Exception thrown when QR URL parsing fails.
///
/// Contains a [messageKey] for localized error display and an optional
/// [detail] for debug logging.
class QrParseException implements Exception {
  /// Localization key for the user-facing error message.
  final String messageKey;

  /// Optional technical detail for logging (not shown to user).
  final String? detail;

  const QrParseException(this.messageKey, {this.detail});

  @override
  String toString() => 'QrParseException($messageKey${detail != null ? ', $detail' : ''})';
}

/// Parse a raw QR code string into connection parameters.
///
/// Expects a URL in the format:
/// `mobileflow://connect?host={ip}&port={port}&token={pair_token}`
///
/// Returns [ConnectionParams] on success.
/// Throws [QrParseException] with a localization key on failure:
/// - `connectQrInvalid` — wrong scheme, host, or missing params
/// - `connectQrInvalidPort` — port is not a valid integer in 1–65535
ConnectionParams parseConnectionUrl(String raw) {
  final Uri uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    throw const QrParseException(
      'connectQrInvalid',
      detail: 'URI parse failed',
    );
  }

  // Validate scheme: must be 'mobileflow'
  if (uri.scheme != 'mobileflow') {
    throw QrParseException(
      'connectQrInvalid',
      detail: 'Expected scheme mobileflow, got ${uri.scheme}',
    );
  }

  // Validate host path: must be 'connect'
  // Uri.parse treats mobileflow://connect?... as host='connect'
  if (uri.host != 'connect') {
    throw QrParseException(
      'connectQrInvalid',
      detail: 'Expected host connect, got ${uri.host}',
    );
  }

  // Extract query parameters (already URL-decoded by Uri.parse)
  final host = uri.queryParameters['host'];
  final portStr = uri.queryParameters['port'];
  final token = uri.queryParameters['token'];

  // Validate required params are present and non-empty
  if (host == null || host.isEmpty) {
    throw const QrParseException(
      'connectQrInvalid',
      detail: 'Missing or empty host parameter',
    );
  }
  if (portStr == null || portStr.isEmpty) {
    throw const QrParseException(
      'connectQrInvalidPort',
      detail: 'Missing or empty port parameter',
    );
  }
  if (token == null || token.isEmpty) {
    throw const QrParseException(
      'connectQrInvalid',
      detail: 'Missing or empty token parameter',
    );
  }

  // Validate port is a valid integer in range 1–65535
  final port = int.tryParse(portStr);
  if (port == null || port < 1 || port > 65535) {
    throw QrParseException(
      'connectQrInvalidPort',
      detail: 'Port out of range: $portStr',
    );
  }

  return ConnectionParams(host: host, port: port, token: token);
}
