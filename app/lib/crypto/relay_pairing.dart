/// relay_pairing.dart — Relay pairing payload encode/decode (Dart side).
///
/// Versioned binary format for exchanging relay connection parameters
/// between Agent and App via QR code or manual text entry.
///
/// Must be wire-compatible with the Python implementation in
/// `agent/src/mobileflow_agent/crypto/relay_pairing.py`.
///
/// Note: The Python module path still uses the legacy `mobileflow_agent`
/// package name. Wire format is identical regardless of package naming.
///
/// Version 1 wire format:
///   Byte 0:     version (0x01)
///   Bytes 1-2:  relay_url length (uint16 big-endian)
///   Bytes 3-N:  relay_url (UTF-8)
///   Bytes N+1 to N+16: device_id (16 bytes raw)
///   Bytes N+17 to N+48: shared_secret (32 bytes raw)
///
/// Encoded as Base64URL (no padding) for QR codes and manual entry.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../utils/logger.dart';

final _log = getLogger('RelayPairing');

/// Current payload format version — increment when wire format changes.
const _payloadVersion = 0x01;

/// Fixed field sizes (bytes).
const _deviceIdLen = 16;
const _sharedSecretLen = 32;

/// Minimum payload: version(1) + url_len(2) + url(>=1) + device_id(16) + secret(32)
const _minPayloadLen = 1 + 2 + 1 + _deviceIdLen + _sharedSecretLen;

/// Decoded relay pairing payload.
class RelayPairingPayload {
  /// Relay server WebSocket URL (e.g. "wss://relay.example.com").
  final String relayUrl;

  /// 16-byte device identifier (raw bytes).
  final Uint8List deviceId;

  /// 32-byte shared secret for E2E encryption.
  final Uint8List sharedSecret;

  const RelayPairingPayload({
    required this.relayUrl,
    required this.deviceId,
    required this.sharedSecret,
  });
}

/// Encode relay pairing parameters into a Base64URL string (no padding).
///
/// Packs [relayUrl], [deviceId], and [sharedSecret] into the versioned
/// binary format. Wire-compatible with the Python `encode_relay_pairing()`.
///
/// Throws [ArgumentError] if field sizes are invalid.
String encodeRelayPairing(
  String relayUrl,
  Uint8List deviceId,
  Uint8List sharedSecret,
) {
  if (deviceId.length != _deviceIdLen) {
    throw ArgumentError(
        'deviceId must be $_deviceIdLen bytes, got ${deviceId.length}');
  }
  if (sharedSecret.length != _sharedSecretLen) {
    throw ArgumentError(
        'sharedSecret must be $_sharedSecretLen bytes, got ${sharedSecret.length}');
  }

  final urlBytes = utf8.encode(relayUrl);
  if (urlBytes.isEmpty) {
    throw ArgumentError('relayUrl must not be empty');
  }
  if (urlBytes.length > 0xFFFF) {
    throw ArgumentError(
        'relayUrl too long: ${urlBytes.length} bytes (max 65535)');
  }

  // Pack: version(1B) + url_len(2B big-endian) + url + device_id + secret
  final totalLen = 1 + 2 + urlBytes.length + _deviceIdLen + _sharedSecretLen;
  final buffer = ByteData(totalLen);
  var offset = 0;

  // Version byte
  buffer.setUint8(offset, _payloadVersion);
  offset += 1;

  // URL length (uint16 big-endian)
  buffer.setUint16(offset, urlBytes.length, Endian.big);
  offset += 2;

  // Copy URL bytes, device_id, and secret into the underlying byte list
  final payload = buffer.buffer.asUint8List();
  payload.setAll(offset, urlBytes);
  offset += urlBytes.length;
  payload.setAll(offset, deviceId);
  offset += _deviceIdLen;
  payload.setAll(offset, sharedSecret);

  // Base64URL without padding — compact for QR codes
  final encoded = base64UrlEncode(payload).replaceAll('=', '');
  _log.fine(
      'Relay 配对码已编码: url_len=${urlBytes.length}, '
      'payload_len=$totalLen, encoded_len=${encoded.length}');
  return encoded;
}

/// Decode a Base64URL relay pairing string into its components.
///
/// Parses the versioned binary format and returns a [RelayPairingPayload].
/// Wire-compatible with the Python `decode_relay_pairing()`.
///
/// Throws [FormatException] if the payload is invalid, wrong version,
/// or too short.
RelayPairingPayload decodeRelayPairing(String encoded) {
  // Restore padding — Base64 requires length to be a multiple of 4
  final remainder = encoded.length % 4;
  final padded = encoded + '=' * ((4 - remainder) % 4);

  Uint8List raw;
  try {
    raw = base64Url.decode(padded);
  } catch (e) {
    throw FormatException('Base64URL 解码失败: $e');
  }

  if (raw.length < _minPayloadLen) {
    throw FormatException(
        '配对码载荷过短: 最少 $_minPayloadLen 字节, 实际 ${raw.length}');
  }

  final version = raw[0];
  if (version != _payloadVersion) {
    throw FormatException('不支持的配对码版本: $version');
  }

  // Read URL length (uint16 big-endian)
  final urlLen = (raw[1] << 8) | raw[2];
  final expectedLen = 3 + urlLen + _deviceIdLen + _sharedSecretLen;
  if (raw.length < expectedLen) {
    throw FormatException(
        '配对码载荷长度不匹配: 期望 $expectedLen, 实际 ${raw.length}');
  }

  // Extract fields
  var offset = 3;
  final relayUrl = utf8.decode(raw.sublist(offset, offset + urlLen));
  offset += urlLen;
  final deviceId = Uint8List.fromList(raw.sublist(offset, offset + _deviceIdLen));
  offset += _deviceIdLen;
  final sharedSecret =
      Uint8List.fromList(raw.sublist(offset, offset + _sharedSecretLen));

  _log.fine(
      'Relay 配对码已解码: version=$version, '
      'relay_url=${relayUrl.length > 40 ? '${relayUrl.substring(0, 40)}...' : relayUrl}, '
      'device_id_len=${deviceId.length}');

  return RelayPairingPayload(
    relayUrl: relayUrl,
    deviceId: deviceId,
    sharedSecret: sharedSecret,
  );
}
