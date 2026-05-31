import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/crypto/crypto_module.dart';

Uint8List _rand(int n) => Uint8List.fromList(List.generate(n, (_) => Random.secure().nextInt(256)));

void main() {
  group('edge cases', () {
    late CryptoModule c;
    setUp(() => c = CryptoModule(_rand(32)));

    test('empty dict', () => expect(c.decrypt(c.encrypt({})), {}));
    test('null value', () {
      final m = {'a': null, 'b': [null, 1]}; expect(c.decrypt(c.encrypt(m)), m);
    });
    test('bool and numbers', () {
      final m = {'t': true, 'f': false, 'z': 0, 'n': -1, 'pi': 3.14};
      final d = c.decrypt(c.encrypt(m));
      expect(d['t'], true); expect(d['f'], false); expect(d['z'], 0);
    });
    test('empty string value', () {
      final m = {'type': '', 'payload': {'c': ''}}; expect(c.decrypt(c.encrypt(m)), m);
    });
    test('list payload', () {
      final m = {'items': [1, 'two', {'three': 3}, [4, 5]]}; expect(c.decrypt(c.encrypt(m)), m);
    });
    test('100 cycles', () {
      for (var i = 0; i < 100; i++) {
        final m = {'i': i, 'd': 'msg_$i'}; expect(c.decrypt(c.encrypt(m)), m);
      }
    });
    test('decrypt empty string throws', () => expect(() => c.decrypt(''), throwsA(anything)));
    test('decrypt garbage base64 throws', () {
      final fake = base64Encode(Uint8List.fromList(utf8.encode('not encrypted')));
      expect(() => c.decrypt(fake), throwsA(anything));
    });
    test('all zero secret', () {
      final zc = CryptoModule(Uint8List(32));
      final m = {'test': 1}; expect(zc.decrypt(zc.encrypt(m)), m);
    });
    test('all 0xFF secret', () {
      final fc = CryptoModule(Uint8List.fromList(List.filled(32, 0xFF)));
      final m = {'test': 1}; expect(fc.decrypt(fc.encrypt(m)), m);
    });
    test('base64url all zero', () {
      final s = Uint8List(32);
      expect(CryptoModule.base64UrlToSecret(CryptoModule.secretToBase64Url(s)), s);
    });
    test('base64url all FF', () {
      final s = Uint8List.fromList(List.filled(32, 0xFF));
      expect(CryptoModule.base64UrlToSecret(CryptoModule.secretToBase64Url(s)), s);
    });
    test('auth challenge tampered fails', () {
      final ch = c.authChallenge();
      final raw = Uint8List.fromList(base64Decode(ch.challenge));
      raw[0] ^= 0xFF;
      expect(CryptoModule.verifyChallenge(base64Encode(raw), ch.publicKey, ch.signature), false);
    });
    test('deeply nested json', () {
      var m = <String, dynamic>{'level': 0};
      var cur = m;
      for (var i = 1; i < 10; i++) { cur['child'] = <String, dynamic>{'level': i}; cur = cur['child'] as Map<String, dynamic>; }
      expect(c.decrypt(c.encrypt(m)), m);
    });
  });
}