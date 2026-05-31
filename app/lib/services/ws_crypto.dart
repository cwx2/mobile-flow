/// ws_crypto.dart — LAN encryption/decryption and credential persistence.
///
/// Wraps [CryptoModule] for message-level encrypt/decrypt and manages
/// session credentials (secret, token, client ID) via [FlutterSecureStorage].
/// Extracted from WebSocketService for independent testing and single
/// responsibility.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/crypto_module.dart';
import '../models/payloads/auth_payloads.g.dart';
import '../utils/logger.dart';

final _log = getLogger('WsCrypto');

/// LAN encryption/decryption and credential persistence.
///
/// Lifecycle:
/// - Call [initFromAuthResult] after receiving `auth.result` with a secret.
/// - Call [encrypt]/[decrypt] for message payload transformation.
/// - Call [persistCredentials] to save session data for reconnection.
/// - Call [restoreSecret] before reconnect to re-init CryptoModule.
/// - Call [reset] on fresh connection to clear in-memory state.
/// - Call [clearSession] when Agent requests re-pairing (`shouldRepair`).
class WsCrypto {
  CryptoModule? _module;

  static const _storage = FlutterSecureStorage();
  static const _keyLanSecret = 'conn_lan_secret';
  static const _keyLanSessionToken = 'conn_lan_session_token';
  static const _keyLanClientId = 'conn_lan_client_id';

  // ── State queries ──

  /// Whether a [CryptoModule] is initialized and ready for encrypt/decrypt.
  bool get isActive => _module != null;

  /// Read the saved client ID from secure storage.
  ///
  /// Returns null if no client ID has been persisted.
  Future<String?> get savedClientId =>
      _storage.read(key: _keyLanClientId);

  // ── Initialization ──

  /// Initialize [CryptoModule] from the Base64-encoded secret in [authResult].
  ///
  /// The Agent includes a 32-byte secret (Base64) in `auth.result` after
  /// both initial pairing and reconnection. If present, all subsequent
  /// messages will be encrypted/decrypted with this secret.
  void initFromAuthResult(AuthResultPayload authResult) {
    final secretB64 = authResult.secret;
    if (secretB64 != null && secretB64.isNotEmpty) {
      try {
        final secretBytes = base64Decode(secretB64);
        _module = CryptoModule(Uint8List.fromList(secretBytes));
        _log.info('🔐 LAN 加密已启用 (${secretBytes.length} 字节密钥)');
      } catch (e) {
        _log.severe('加密密钥初始化失败: $e');
        _module = null;
      }
    }
  }

  /// Clear the in-memory [CryptoModule] reference.
  ///
  /// Called before a fresh LAN connection to ensure no stale key is used.
  void reset() {
    _module = null;
  }

  // ── Encrypt / Decrypt ──

  /// Encrypt a message payload for sending over LAN.
  ///
  /// Returns a Base64-encoded ciphertext string.
  /// Throws if [CryptoModule] is not initialized.
  String encrypt(Map<String, dynamic> payload) {
    return _module!.encrypt(payload);
  }

  /// Decrypt a raw ciphertext string received from the Agent.
  ///
  /// Returns the parsed JSON map.
  /// Throws if decryption fails (key mismatch, tampered data).
  Map<String, dynamic> decrypt(String ciphertext) {
    return _module!.decrypt(ciphertext);
  }

  // ── Credential persistence ──

  /// Persist LAN session token, encryption secret, and client ID.
  ///
  /// Called after successful auth so the app can reconnect without
  /// re-pairing. Failures are logged but not propagated — reconnect
  /// will fall back to pairing if credentials are missing.
  Future<void> persistCredentials(
    String sessionToken,
    String? secretB64, {
    String? clientId,
  }) async {
    try {
      if (sessionToken.isNotEmpty) {
        await _storage.write(key: _keyLanSessionToken, value: sessionToken);
      }
      if (secretB64 != null && secretB64.isNotEmpty) {
        await _storage.write(key: _keyLanSecret, value: secretB64);
        _log.fine('LAN 加密密钥已持久化');
      }
      if (clientId != null && clientId.isNotEmpty) {
        await _storage.write(key: _keyLanClientId, value: clientId);
      }
    } catch (e) {
      _log.warning('持久化 LAN 凭据失败: $e');
    }
  }

  /// Restore encryption secret from secure storage for LAN reconnection.
  ///
  /// Called before sending `auth.connect` so that [CryptoModule] is ready
  /// if the Agent responds with encrypted messages immediately.
  Future<void> restoreSecret() async {
    try {
      final secretB64 = await _storage.read(key: _keyLanSecret);
      if (secretB64 != null && secretB64.isNotEmpty) {
        final secretBytes = base64Decode(secretB64);
        _module = CryptoModule(Uint8List.fromList(secretBytes));
        _log.info('🔐 LAN 加密密钥已从存储恢复');
      }
    } catch (e) {
      _log.warning('恢复 LAN 加密密钥失败: $e');
      _module = null;
    }
  }

  /// Delete session token and client ID from secure storage.
  ///
  /// Called when the Agent responds with `shouldRepair`, indicating
  /// the session is stale and the app should fall through to pairing.
  Future<void> clearSession() async {
    await _storage.delete(key: _keyLanSessionToken);
    await _storage.delete(key: _keyLanClientId);
  }
}
