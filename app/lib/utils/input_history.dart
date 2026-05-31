/// input_history.dart — Persistent input history with frequency-based retention.
///
/// Stores up to [_maxEntries] input entries with use counts. When the limit
/// is exceeded, the least-used entry is evicted (not the oldest). This keeps
/// frequently used prompts available for quick reuse.
///
/// Persistence: entries are stored as a JSON array in SharedPreferences
/// under the key [_storageKey]. Loaded once on init, saved after each push.
///
/// Used by: ChatInputBar toolbar history button and input field.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'logger.dart';

final _log = getLogger('InputHistory');

/// Maximum number of history entries to retain.
const int _maxEntries = 50;

/// SharedPreferences key for persisted history data.
const String _storageKey = 'input_history_v1';

/// A single input history entry with use count tracking.
class HistoryEntry {
  final String text;
  int useCount;
  DateTime lastUsed;

  HistoryEntry({
    required this.text,
    this.useCount = 1,
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'text': text,
        'useCount': useCount,
        'lastUsed': lastUsed.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      text: json['text'] as String? ?? '',
      useCount: json['useCount'] as int? ?? 1,
      lastUsed: DateTime.tryParse(json['lastUsed'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Persistent input history with frequency-based eviction.
///
/// Entries are deduplicated by text content. Pushing an existing entry
/// increments its [HistoryEntry.useCount] and updates [HistoryEntry.lastUsed].
/// When the list exceeds [_maxEntries], the entry with the lowest useCount
/// is removed (ties broken by oldest lastUsed).
///
/// Call [load] once before use to restore from SharedPreferences.
class InputHistory {
  final List<HistoryEntry> _entries = [];
  int _cursor = -1;
  bool _loaded = false;

  /// All entries sorted by lastUsed descending (most recent first) for UI display.
  List<HistoryEntry> get entries => List.unmodifiable(
        List<HistoryEntry>.from(_entries)
          ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed)),
      );

  /// Whether history has any entries (for toolbar button visibility).
  bool get isNotEmpty => _entries.isNotEmpty;

  /// Load persisted history from SharedPreferences.
  ///
  /// Safe to call multiple times — only loads once. Silently handles
  /// corrupt data by starting with an empty list.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> parsed = jsonDecode(raw) as List;
        _entries.clear();
        for (final item in parsed) {
          if (item is Map<String, dynamic>) {
            final entry = HistoryEntry.fromJson(item);
            if (entry.text.isNotEmpty) {
              _entries.add(entry);
            }
          }
        }
        _log.fine('输入历史已加载: ${_entries.length} 条');
      }
    } catch (e) {
      _log.warning('输入历史加载失败，使用空列表: $e');
      _entries.clear();
    }
  }

  /// Record an input entry. Increments useCount if already exists.
  ///
  /// Persists to SharedPreferences after each push.
  Future<void> push(String text) async {
    if (text.trim().isEmpty) return;
    final trimmed = text.trim();

    // Deduplicate: find existing entry and increment useCount
    final existing = _entries.indexWhere((e) => e.text == trimmed);
    if (existing >= 0) {
      _entries[existing].useCount++;
      _entries[existing].lastUsed = DateTime.now();
    } else {
      _entries.add(HistoryEntry(text: trimmed));
      // Evict least-used entry when over limit
      if (_entries.length > _maxEntries) {
        _evictLeastUsed();
      }
    }

    _cursor = -1;
    await _save();
  }

  /// Navigate up through history (returns null if no more).
  ///
  /// Iterates entries sorted by lastUsed descending (most recent first).
  String? previous(String current) {
    if (_entries.isEmpty) return null;
    final sorted = entries; // already sorted by lastUsed desc
    if (_cursor == -1) {
      _cursor = 0;
    } else if (_cursor < sorted.length - 1) {
      _cursor++;
    } else {
      return null;
    }
    return sorted[_cursor].text;
  }

  /// Navigate down through history.
  String? next() {
    if (_cursor == -1) return null;
    final sorted = entries;
    if (_cursor > 0) {
      _cursor--;
      return sorted[_cursor].text;
    }
    _cursor = -1;
    return '';
  }

  /// Reset cursor (when user starts new input).
  void reset() => _cursor = -1;

  /// Remove the entry with the lowest useCount.
  /// Ties broken by oldest lastUsed.
  void _evictLeastUsed() {
    if (_entries.isEmpty) return;
    int minIdx = 0;
    for (int i = 1; i < _entries.length; i++) {
      final current = _entries[i];
      final minEntry = _entries[minIdx];
      if (current.useCount < minEntry.useCount ||
          (current.useCount == minEntry.useCount &&
              current.lastUsed.isBefore(minEntry.lastUsed))) {
        minIdx = i;
      }
    }
    final evicted = _entries.removeAt(minIdx);
    _log.fine('淘汰低频历史: "${evicted.text.substring(0, evicted.text.length.clamp(0, 30))}..." '
        'useCount=${evicted.useCount}');
  }

  /// Persist current entries to SharedPreferences.
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, json);
    } catch (e) {
      _log.warning('输入历史保存失败: $e');
    }
  }
}
