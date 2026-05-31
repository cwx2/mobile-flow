/// crypto_module.dart — End-to-end encryption module (Dart side).
//
// Module: crypto/
// Responsibilities:
//   1. Message encrypt/decrypt (NaCl secretbox, XSalsa20-Poly1305 symmetric encryption)
//   2. Ed25519 signature authentication (for Relay Server challenge-response)
//   3. X25519 public-key encrypt/decrypt (for pairing phase)
//   4. Key derivation (derive signing key and encryption key from 32-byte secret)
//
// Callers:
//   - services/connection_manager.dart (Relay mode message encrypt/decrypt)
//   - screens/connect_screen.dart (pairing flow)
//
// Reference implementations:
//   - Python-side crypto_module.py (must interoperate)
//   - Happy encryption.ts encryptLegacy/decryptLegacy
//
// Encryption format (consistent with Python side):
//   secretbox: nonce(24B) + ciphertext
//   output: Base64(nonce + ciphertext)
//
// Design decisions:
//   - secretbox symmetric encryption: use secret directly as key (matches Python PyNaCl)
//   - Ed25519 signing: derive from secret as seed (matches Python PyNaCl)
//   - X25519 public-key encryption: use independently generated key pair (pinenacl does not support Ed25519->X25519 conversion)
//     Exchange X25519 public keys via QR code during pairing, no key conversion needed

import 'dart:convert';
import 'dart:math';

import 'package:pinenacl/ed25519.dart';
import 'package:pinenacl/x25519.dart';

import '../utils/logger.dart';

final _log = getLogger('CryptoModule');

/// Ed25519 signature authentication challenge data.
class AuthChallenge {
  /// Base64-encoded 32-byte random challenge.
  final String challenge;

  /// Base64-encoded Ed25519 public key.
  final String publicKey;

  /// Base64-encoded signature.
  final String signature;

  const AuthChallenge({
    required this.challenge,
    required this.publicKey,
    required this.signature,
  });

  Map<String, String> toJson() => {
        'challenge': challenge,
        'public_key': publicKey,
        'signature': signature,
      };
}

/// End-to-end encryption module.
///
/// Implemented with TweetNaCl (pinenacl package):
/// - secretbox: XSalsa20-Poly1305 symmetric encryption (message encryption, high performance)
/// - sign: Ed25519 signatures (Relay authentication)
/// - box: X25519 ECDH + XSalsa20-Poly1305 (key exchange, pairing phase)
///
/// Initialization:
/// - From a 32-byte secret (key seed shared during pairing)
/// - Fully interoperable with Python-side CryptoModule (secretbox + Ed25519 signing)
class CryptoModule {
  final Uint8List _secret;

  /// Secretbox symmetric encryption key (uses secret directly).
  late final SecretBox _secretBox;

  /// Ed25519 signing key (derived from secret as seed).
  late final SigningKey _signingKey;

  /// Ed25519 verification public key.
  late final VerifyKey _verifyKey;

  /// Initialize the encryption module from a 32-byte secret.
  ///
  /// [secret] must be 32 bytes, shared between Agent and App during pairing.
  /// Corresponds directly to Python-side `CryptoModule(secret)`.
  CryptoModule(this._secret) {
    if (_secret.length != 32) {
      throw ArgumentError('secret 必须是 32 字节，实际 ${_secret.length} 字节');
    }

    // Secretbox symmetric encryption (matches Python PyNaCl SecretBox)
    _secretBox = SecretBox(Uint8List.fromList(_secret));

    // Ed25519 signing key (derived from seed, matches Python PyNaCl SigningKey(seed=))
    _signingKey = SigningKey.fromSeed(_secret);
    _verifyKey = _signingKey.verifyKey;
  }

  // ── Symmetric encryption (secretbox, for message encryption) ──

  /// Encrypt a MobileFlow Message to a Base64 string.
  ///
  /// Flow: JSON serialize -> UTF-8 encode -> secretbox encrypt -> Base64 encode.
  /// Output format: Base64(nonce(24B) + ciphertext).
  ///
  /// Fully interoperable with Python-side `CryptoModule.encrypt()`.
  String encrypt(Map<String, dynamic> message) {
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(message)));
    final encrypted = _secretBox.encrypt(plaintext);
    // _log.fine('Message encrypted: ${plaintext.length} -> ${encrypted.length} bytes');
    // EncryptedMessage contains nonce(24B) + ciphertext, matches PyNaCl format
    return base64Encode(Uint8List.fromList(encrypted));
  }

  /// Decrypt a Base64 string to a MobileFlow Message.
  ///
  /// Flow: Base64 decode -> secretbox decrypt -> UTF-8 decode -> JSON deserialize.
  ///
  /// Fully interoperable with Python-side `CryptoModule.decrypt()`.
  ///
  /// Throws if decryption fails (ciphertext tampered or key mismatch).
  Map<String, dynamic> decrypt(String ciphertextB64) {
    try {
      final encrypted = base64Decode(ciphertextB64);
      // PyNaCl format: nonce(24B) + ciphertext
      final nonce = Uint8List.fromList(encrypted.sublist(0, 24));
      final cipherText = Uint8List.fromList(encrypted.sublist(24));
      final decrypted = _secretBox.decrypt(
        EncryptedMessage(nonce: nonce, cipherText: cipherText),
      );
      // _log.fine('Message decrypted: ${encrypted.length} -> ${decrypted.length} bytes');
      return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    } catch (e) {
      _log.severe('消息解密失败: $e');
      rethrow;
    }
  }

  // ── Ed25519 signature authentication (for Relay Server auth) ──

  /// Generate an authentication challenge.
  ///
  /// Corresponds directly to Python-side `CryptoModule.auth_challenge()`.
  /// Relay Server verifies with `verify_challenge()`.
  AuthChallenge authChallenge() {
    final challenge = _randomBytes(32);
    // pinenacl SigningKey.sign() returns SignedMessage = signature(64B) + message
    final signedMsg = _signingKey.sign(challenge);
    final signature = Uint8List.fromList(signedMsg.signature.sublist(0, 64));

    return AuthChallenge(
      challenge: base64Encode(challenge),
      publicKey: base64Encode(Uint8List.fromList(_verifyKey)),
      signature: base64Encode(signature),
    );
  }

  /// Verify an authentication challenge (can be used by App to verify Agent identity).
  ///
  /// Corresponds directly to Python-side `CryptoModule.verify_challenge()`.
  static bool verifyChallenge(
    String challengeB64,
    String publicKeyB64,
    String signatureB64,
  ) {
    try {
      final challenge = base64Decode(challengeB64);
      final publicKeyBytes = base64Decode(publicKeyB64);
      final signature = base64Decode(signatureB64);

      if (publicKeyBytes.length != 32 || signature.length != 64) {
        return false;
      }

      final verifyKey = VerifyKey(Uint8List.fromList(publicKeyBytes));
      // pinenacl: verifySignedMessage accepts SignedMessage(sig64 + msg)
      final signedMessage = Uint8List.fromList([...signature, ...challenge]);
      verifyKey.verifySignedMessage(
        signedMessage: SignedMessage.fromList(signedMessage: signedMessage),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Public-key encryption (box, for pairing phase) ──

  /// Encrypt data with the recipient's public key (forward secrecy).
  ///
  /// Uses an ephemeral key pair: generate ephemeral X25519 key -> box encrypt.
  /// Output: ephemeral_pubkey(32B) + nonce(24B) + ciphertext.
  Uint8List encryptForPublicKey(Uint8List data, Uint8List recipientPublicKey) {
    // Generate ephemeral key pair
    final ephemeralKey = PrivateKey.generate();
    final recipientKey = PublicKey(recipientPublicKey);

    // Box encrypt
    final box = Box(myPrivateKey: ephemeralKey, theirPublicKey: recipientKey);
    final encrypted = box.encrypt(data);

    // Concatenate: ephemeral pubkey(32B) + encrypted data(nonce + ciphertext)
    final result = Uint8List(32 + encrypted.length);
    result.setAll(0, ephemeralKey.publicKey);
    result.setAll(32, encrypted);
    return result;
  }

  /// Decrypt public-key encrypted data with an X25519 private key.
  ///
  /// Input format: ephemeral_pubkey(32B) + nonce(24B) + ciphertext.
  ///
  /// [privateKeyBytes] is an X25519 private key (32 bytes).
  static Uint8List decryptFromPublicKeyWithPrivate(
      Uint8List data, Uint8List privateKeyBytes) {
    if (data.length < 32 + 24 + 16) {
      throw ArgumentError('加密数据太短: ${data.length} 字节，最少需要 72 字节');
    }

    final ephemeralPubKey = PublicKey(Uint8List.fromList(data.sublist(0, 32)));
    final encryptedData = Uint8List.fromList(data.sublist(32));
    final privKey = PrivateKey(privateKeyBytes);

    final box = Box(myPrivateKey: privKey, theirPublicKey: ephemeralPubKey);
    return Uint8List.fromList(box.decrypt(EncryptedMessage(
      nonce: Uint8List.fromList(encryptedData.sublist(0, 24)),
      cipherText: Uint8List.fromList(encryptedData.sublist(24)),
    )));
  }

  // ── Utility methods ──

  /// Base64-encoded Ed25519 verification public key.
  String get verifyKeyB64 => base64Encode(Uint8List.fromList(_verifyKey));

  /// Generate a 32-byte random secret (for new pairing).
  static Uint8List generateSecret() {
    _log.info('生成新的 32 字节配对密钥');
    return _randomBytes(32);
  }

  /// Encode secret as Base64URL (for QR code / deep link).
  static String secretToBase64Url(Uint8List secret) {
    return base64UrlEncode(secret).replaceAll('=', '');
  }

  /// Decode Base64URL back to secret.
  static Uint8List base64UrlToSecret(String b64url) {
    final padding = (4 - b64url.length % 4) % 4;
    final padded = b64url + '=' * padding;
    return base64Url.decode(padded);
  }

  /// Generate cryptographically secure random bytes.
  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)));
  }
}
