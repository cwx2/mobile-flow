/// key_store.dart — Key persistence store (Dart side).
//
// Module: crypto/
// Responsibilities:
//   1. Securely store pairing secret (key seed)
//   2. Manage list of paired Agents
//   3. Device revocation (delete keys)
//
// Callers:
//   - screens/connect_screen.dart (pairing flow)
//   - services/connection_manager.dart (load keys to establish encrypted connection)
//   - screens/settings_screen.dart (device management UI)
//
// Storage strategy:
//   - secret stored in flutter_secure_storage (Android Keystore / iOS Keychain)
//   - Agent metadata stored in flutter_secure_storage (JSON serialized)

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/logger.dart';

final _log = getLogger('KeyStore');

/// Paired Agent information.
class AgentInfo {
  /// Agent unique identifier.
  final String deviceId;

  /// Agent name (hostname).
  final String name;

  /// Agent platform (macos / linux / windows).
  final String platform;

  /// Relay Server address.
  final String relayUrl;

  /// Pairing timestamp (milliseconds since epoch).
  final int pairedAt;

  /// Last seen timestamp (milliseconds since epoch).
  int lastSeen;

  AgentInfo({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.relayUrl,
    required this.pairedAt,
    this.lastSeen = 0,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': name,
        'platform': platform,
        'relay_url': relayUrl,
        'paired_at': pairedAt,
        'last_seen': lastSeen,
      };

  factory AgentInfo.fromJson(Map<String, dynamic> json) => AgentInfo(
        deviceId: json['device_id'] as String,
        name: json['name'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        relayUrl: json['relay_url'] as String? ?? '',
        pairedAt: json['paired_at'] as int? ?? 0,
        lastSeen: json['last_seen'] as int? ?? 0,
      );
}

/// Key persistence store.
///
/// Uses flutter_secure_storage for secure key storage:
/// - Android: Android Keystore
/// - iOS: iOS Keychain
class KeyStore {
  static const _keyPrefix = 'mobileflow_secret_';
  static const _agentsListKey = 'mobileflow_agents_list';

  final FlutterSecureStorage _storage;

  KeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // ── Secret storage ──

  /// Save a pairing secret.
  Future<void> saveSecret(String deviceId, Uint8List secret) async {
    if (secret.length != 32) {
      throw ArgumentError('secret 必须是 32 字节，实际 ${secret.length} 字节');
    }
    _log.info('保存配对密钥: deviceId=${deviceId.substring(0, min(8, deviceId.length))}...');
    await _storage.write(
      key: '$_keyPrefix$deviceId',
      value: _bytesToHex(secret),
    );
  }

  /// Load a pairing secret.
  Future<Uint8List?> loadSecret(String deviceId) async {
    _log.fine('加载配对密钥: deviceId=${deviceId.substring(0, min(8, deviceId.length))}...');
    final hex = await _storage.read(key: '$_keyPrefix$deviceId');
    if (hex == null) {
      _log.fine('密钥未找到: deviceId=${deviceId.substring(0, min(8, deviceId.length))}...');
      return null;
    }
    try {
      return _hexToBytes(hex);
    } catch (e) {
      _log.severe('密钥解析失败: deviceId=${deviceId.substring(0, min(8, deviceId.length))}..., error=$e');
      return null;
    }
  }

  /// Delete a pairing secret.
  Future<bool> deleteSecret(String deviceId) async {
    final exists = await _storage.read(key: '$_keyPrefix$deviceId');
    if (exists == null) return false;
    await _storage.delete(key: '$_keyPrefix$deviceId');
    return true;
  }

  // ── Agent metadata management ──

  /// Get the list of all paired Agents.
  Future<List<AgentInfo>> listAgents() async {
    final json = await _storage.read(key: _agentsListKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => AgentInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Add a paired Agent (save secret + metadata).
  Future<void> addAgent(AgentInfo agent, Uint8List secret) async {
    _log.info('添加设备: name=${agent.name}, platform=${agent.platform}');
    await saveSecret(agent.deviceId, secret);

    final agents = await listAgents();
    agents.removeWhere((a) => a.deviceId == agent.deviceId);
    agents.add(agent);
    await _saveAgentsList(agents);
  }

  /// Revoke a paired Agent (delete secret + metadata).
  Future<bool> removeAgent(String deviceId) async {
    _log.info('撤销设备: deviceId=${deviceId.substring(0, min(8, deviceId.length))}...');
    await deleteSecret(deviceId);

    final agents = await listAgents();
    final before = agents.length;
    agents.removeWhere((a) => a.deviceId == deviceId);
    await _saveAgentsList(agents);
    return agents.length < before;
  }

  /// Get information for a specific Agent.
  Future<AgentInfo?> getAgent(String deviceId) async {
    final agents = await listAgents();
    try {
      return agents.firstWhere((a) => a.deviceId == deviceId);
    } catch (_) {
      return null;
    }
  }

  /// Update the last-seen timestamp for an Agent.
  Future<void> updateLastSeen(String deviceId) async {
    final agents = await listAgents();
    for (final a in agents) {
      if (a.deviceId == deviceId) {
        a.lastSeen = DateTime.now().millisecondsSinceEpoch;
        await _saveAgentsList(agents);
        return;
      }
    }
  }

  /// Whether any paired Agents exist.
  Future<bool> hasAgents() async {
    final agents = await listAgents();
    return agents.isNotEmpty;
  }

  // ── Internal methods ──

  Future<void> _saveAgentsList(List<AgentInfo> agents) async {
    final json = jsonEncode(agents.map((a) => a.toJson()).toList());
    await _storage.write(key: _agentsListKey, value: json);
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
