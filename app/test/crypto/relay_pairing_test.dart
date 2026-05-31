// Feature: connection-architecture-overhaul
//
// Relay pairing payload round-trip tests.
//
// Verifies that encodeRelayPairing / decodeRelayPairing are
// wire-compatible: encode then decode must produce the original
// (relay_url, device_id, shared_secret) triple.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/crypto/relay_pairing.dart';

Uint8List _rand(int n) =>
    Uint8List.fromList(List.generate(n, (_) => Random.secure().nextInt(256)));

Uint8List _fixed(int n, int fill) => Uint8List.fromList(List.filled(n, fill));

/// Decode a no-padding Base64URL string into raw bytes.
Uint8List _decodeB64Url(String s) {
  final rem = s.length % 4;
  final padded = s + '=' * ((4 - rem) % 4);
  return base64Url.decode(padded);
}

/// Encode raw bytes as no-padding Base64URL.
String _encodeB64Url(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

void main() {
  group('relay pairing round-trip', () {
    // Feature: connection-architecture-overhaul
    test('test_encode_decode_roundtrip_basic', () {
      final url = 'wss://relay.example.com';
      final deviceId = _fixed(16, 0xAB);
      final secret = _fixed(32, 0xCD);

      final encoded = encodeRelayPairing(url, deviceId, secret);
      final decoded = decodeRelayPairing(encoded);

      expect(decoded.relayUrl, url);
      expect(decoded.deviceId, deviceId);
      expect(decoded.sharedSecret, secret);
    });

    // Feature: connection-architecture-overhaul
    test('test_encode_decode_roundtrip_unicode_url', () {
      // URL with unicode path segment — the codec must handle
      // raw UTF-8 bytes correctly regardless of character set.
      final url = 'wss://中继.example.com/连接';
      final deviceId = _rand(16);
      final secret = _rand(32);

      final encoded = encodeRelayPairing(url, deviceId, secret);
      final decoded = decodeRelayPairing(encoded);

      expect(decoded.relayUrl, url);
      expect(decoded.deviceId, deviceId);
      expect(decoded.sharedSecret, secret);
    });

    // Feature: connection-architecture-overhaul
    test('test_roundtrip_multiple_urls', () {
      final urls = [
        'wss://relay.example.com',
        'ws://192.168.1.100:8080',
        'wss://relay.example.com/v1/connect',
        'wss://relay.example.com:443/path?query=1',
        'ws://localhost:3000',
      ];
      final deviceId = _rand(16);
      final secret = _rand(32);

      for (final url in urls) {
        final encoded = encodeRelayPairing(url, deviceId, secret);
        final decoded = decodeRelayPairing(encoded);
        expect(decoded.relayUrl, url, reason: 'round-trip failed for: $url');
        expect(decoded.deviceId, deviceId);
        expect(decoded.sharedSecret, secret);
      }
    });
  });

  group('relay pairing decode errors', () {
    // Feature: connection-architecture-overhaul
    test('test_decode_invalid_version', () {
      final url = 'wss://relay.example.com';
      final deviceId = _fixed(16, 0x01);
      final secret = _fixed(32, 0x02);

      // Encode a valid payload, then tamper the version byte
      final encoded = encodeRelayPairing(url, deviceId, secret);
      final raw = _decodeB64Url(encoded);
      raw[0] = 0x99; // wrong version
      final tampered = _encodeB64Url(raw);

      expect(() => decodeRelayPairing(tampered), throwsFormatException);
    });

    // Feature: connection-architecture-overhaul
    test('test_decode_too_short', () {
      // 3 bytes: version + url_len, but no url/deviceId/secret
      final shortPayload = _encodeB64Url(Uint8List.fromList([0x01, 0x00, 0x01]));
      expect(() => decodeRelayPairing(shortPayload), throwsFormatException);
    });

    // Feature: connection-architecture-overhaul
    test('test_decode_invalid_base64', () {
      expect(
        () => decodeRelayPairing('!!!not-valid-base64!!!'),
        throwsFormatException,
      );
    });
  });

  group('relay pairing encode errors', () {
    // Feature: connection-architecture-overhaul
    test('test_encode_empty_url_throws', () {
      expect(
        () => encodeRelayPairing('', _rand(16), _rand(32)),
        throwsArgumentError,
      );
    });

    // Feature: connection-architecture-overhaul
    test('test_encode_wrong_device_id_length', () {
      // Too short (8 bytes)
      expect(
        () => encodeRelayPairing('wss://r.co', _rand(8), _rand(32)),
        throwsArgumentError,
      );
      // Too long (32 bytes)
      expect(
        () => encodeRelayPairing('wss://r.co', _rand(32), _rand(32)),
        throwsArgumentError,
      );
    });

    // Feature: connection-architecture-overhaul
    test('test_encode_wrong_secret_length', () {
      // Too short (16 bytes)
      expect(
        () => encodeRelayPairing('wss://r.co', _rand(16), _rand(16)),
        throwsArgumentError,
      );
      // Too long (64 bytes)
      expect(
        () => encodeRelayPairing('wss://r.co', _rand(16), _rand(64)),
        throwsArgumentError,
      );
    });
  });
}
