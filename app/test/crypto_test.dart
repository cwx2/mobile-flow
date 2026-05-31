import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/crypto/crypto_module.dart';

Uint8List _rand(int n) =>
    Uint8List.fromList(List.generate(n, (_) => Random.secure().nextInt(256)));

void main() {
  group('init', () {
    test('32B',
        () => expect(CryptoModule(_rand(32)).verifyKeyB64.isNotEmpty, true));
    test('16B',
        () => expect(() => CryptoModule(_rand(16)), throwsArgumentError));
    test('64B',
        () => expect(() => CryptoModule(_rand(64)), throwsArgumentError));
    test('0B',
        () => expect(() => CryptoModule(Uint8List(0)), throwsArgumentError));
    test('same', () {
      final s = _rand(32);
      expect(CryptoModule(s).verifyKeyB64,
          CryptoModule(Uint8List.fromList(s)).verifyKeyB64);
    });
    test(
        'diff',
        () => expect(CryptoModule(_rand(32)).verifyKeyB64,
            isNot(CryptoModule(_rand(32)).verifyKeyB64)));
  });

  group('secretbox', () {
    late CryptoModule c;
    setUp(() => c = CryptoModule(_rand(32)));
    test('roundtrip', () {
      final m = {
        'type': 'chat.send',
        'payload': {'message': 'hello'}
      };
      expect(c.decrypt(c.encrypt(m)), m);
    });
    test('nested', () {
      final m = {
        't': 's',
        'p': {
          'chunk': {'t': 'text', 'c': 'abc'}
        }
      };
      expect(c.decrypt(c.encrypt(m)), m);
    });
    test('empty', () {
      final m = {'t': 'p'};
      expect(c.decrypt(c.encrypt(m)), m);
    });
    test('nonce', () {
      final m = {'t': '1'};
      expect(c.encrypt(m), isNot(c.encrypt(m)));
    });
    test(
        'wrong key',
        () => expect(() => CryptoModule(_rand(32)).decrypt(c.encrypt({'t': 1})),
            throwsA(anything)));
    test('tampered', () {
      final r = Uint8List.fromList(base64Decode(c.encrypt({'t': 1})));
      r[30] ^= 0xFF;
      expect(() => c.decrypt(base64Encode(r)), throwsA(anything));
    });
    test('100KB', () {
      final m = {'c': 'x' * 100000};
      expect(c.decrypt(c.encrypt(m)), m);
    });
    test('unicode', () {
      final m = {'c': 'hello world'};
      expect(c.decrypt(c.encrypt(m)), m);
    });
    test('cross', () {
      final s = _rand(32);
      expect(
          CryptoModule(Uint8List.fromList(s))
              .decrypt(CryptoModule(s).encrypt({'f': 'a'})),
          {'f': 'a'});
    });
  });

  group('Ed25519', () {
    late CryptoModule c;
    setUp(() => c = CryptoModule(_rand(32)));
    test('fields', () {
      final h = c.authChallenge();
      expect(
          h.challenge.isNotEmpty &&
              h.publicKey.isNotEmpty &&
              h.signature.isNotEmpty,
          true);
    });
    test('verify', () {
      final h = c.authChallenge();
      expect(
          CryptoModule.verifyChallenge(h.challenge, h.publicKey, h.signature),
          true);
    });
    test('wrong sig', () {
      final h = c.authChallenge();
      final o = CryptoModule(_rand(32)).authChallenge();
      expect(
          CryptoModule.verifyChallenge(h.challenge, h.publicKey, o.signature),
          false);
    });
    test('wrong pk', () {
      final h = c.authChallenge();
      final o = CryptoModule(_rand(32)).authChallenge();
      expect(
          CryptoModule.verifyChallenge(h.challenge, o.publicKey, h.signature),
          false);
    });
    test('unique', () {
      final a = c.authChallenge();
      final b = c.authChallenge();
      expect(a.challenge, isNot(b.challenge));
      expect(a.publicKey, b.publicKey);
    });
    test('bad b64',
        () => expect(CryptoModule.verifyChallenge('!', '!', '!'), false));
    test('lengths', () {
      final h = c.authChallenge();
      expect(base64Decode(h.challenge).length, 32);
      expect(base64Decode(h.publicKey).length, 32);
      expect(base64Decode(h.signature).length, 64);
    });
  });

  group('Base64URL', () {
    test('roundtrip', () {
      final s = _rand(32);
      expect(
          CryptoModule.base64UrlToSecret(CryptoModule.secretToBase64Url(s)), s);
    });
    test('safe', () {
      for (var i = 0; i < 20; i++) {
        final e = CryptoModule.secretToBase64Url(_rand(32));
        expect(e.contains('+') || e.contains('/') || e.contains('='), false);
      }
    });
    test('gen32', () => expect(CryptoModule.generateSecret().length, 32));
    test(
        'genUniq',
        () => expect(CryptoModule.generateSecret(),
            isNot(CryptoModule.generateSecret())));
  });

  group('interop', () {
    test('deterministic', () {
      final s = Uint8List.fromList(List.generate(32, (i) => i));
      expect(CryptoModule(s).verifyKeyB64,
          CryptoModule(Uint8List.fromList(s)).verifyKeyB64);
    });
    test('format', () {
      final s = Uint8List.fromList(List.generate(32, (i) => i));
      final c = CryptoModule(s);
      final m = {'type': 'test', 'v': 42};
      final e = c.encrypt(m);
      expect(base64Decode(e).length, greaterThanOrEqualTo(40));
      expect(CryptoModule(Uint8List.fromList(s)).decrypt(e), m);
    });
    test('verifyKey matches Python', () {
      final s = Uint8List.fromList(List.generate(32, (i) => i));
      expect(CryptoModule(s).verifyKeyB64,
          'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');
    });
    test('decrypt Python encrypted', () {
      final s = Uint8List.fromList(List.generate(32, (i) => i));
      final c = CryptoModule(s);
      final dec = c.decrypt(
          'kkxukpBGSoEib//bXU9r3u/PE77MuyF+BdA6ONaw87V6pdeAYSl4c8jekZMC0KdARwVXvn2eFgLzUwkxRBExZqFrVN8n');
      expect(dec, {'type': 'test', 'value': 42});
    });
  });
}
