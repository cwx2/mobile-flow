// WsCrypto tests
//
// Covers: isActive state, initFromAuthResult, reset, encrypt/decrypt
// round-trip, and error cases for uninitialized crypto.
//
// Note: FlutterSecureStorage is not available in unit tests, so
// persist/restore tests are skipped. Focus is on in-memory crypto.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/payloads/auth_payloads.g.dart';
import 'package:mobileflow/services/ws_crypto.dart';

void main() {
  late WsCrypto crypto;

  /// Generate a deterministic 32-byte test key.
  Uint8List testKey() =>
      Uint8List.fromList(List.generate(32, (i) => i));

  setUp(() {
    crypto = WsCrypto();
  });

  group('WsCrypto', () {
    test('isActive 初始为 false', () {
      expect(crypto.isActive, false);
    });

    test('initFromAuthResult 使用有效 secret 后 isActive 为 true', () {
      final key = testKey();
      final secretB64 = base64Encode(key);
      final authResult = AuthResultPayload(
        success: true,
        secret: secretB64,
      );
      crypto.initFromAuthResult(authResult);
      expect(crypto.isActive, true);
    });

    test('initFromAuthResult 使用空 secret 保持 isActive 为 false', () {
      final authResult = AuthResultPayload(
        success: true,
        secret: '',
      );
      crypto.initFromAuthResult(authResult);
      expect(crypto.isActive, false);
    });

    test('initFromAuthResult 使用 null secret 保持 isActive 为 false', () {
      const authResult = AuthResultPayload(
        success: true,
        secret: null,
      );
      crypto.initFromAuthResult(authResult);
      expect(crypto.isActive, false);
    });

    test('reset() 将 isActive 设为 false', () {
      final key = testKey();
      final secretB64 = base64Encode(key);
      crypto.initFromAuthResult(AuthResultPayload(
        success: true,
        secret: secretB64,
      ));
      expect(crypto.isActive, true);

      crypto.reset();
      expect(crypto.isActive, false);
    });

    test('encrypt → decrypt 往返保持 payload 不变', () {
      final key = testKey();
      final secretB64 = base64Encode(key);
      crypto.initFromAuthResult(AuthResultPayload(
        success: true,
        secret: secretB64,
      ));

      final original = {
        'type': 'chat.send',
        'payload': {
          'cli': 'test-cli',
          'message': 'Hello, world! 你好世界 🌍',
        },
      };

      final encrypted = crypto.encrypt(original);
      // Encrypted output should be a Base64 string, not JSON
      expect(encrypted, isNot(startsWith('{')));

      final decrypted = crypto.decrypt(encrypted);
      expect(decrypted['type'], original['type']);
      expect(
        (decrypted['payload'] as Map)['message'],
        (original['payload'] as Map)['message'],
      );
    });

    test('encrypt 在未初始化时抛出异常', () {
      expect(crypto.isActive, false);
      expect(
        () => crypto.encrypt({'type': 'test'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('decrypt 在未初始化时抛出异常', () {
      expect(crypto.isActive, false);
      expect(
        () => crypto.decrypt('some_base64_string'),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
