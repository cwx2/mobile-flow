/// locale_service.dart — Language preference manager.
///
/// Manages the app locale (language) with persistence via SharedPreferences.
/// Null locale means "follow system language" (the default).
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

final _log = getLogger('LocaleService');

/// Language preference manager with persistence.
///
/// Exposes the current [locale] and notifies listeners on change.
/// A null locale means "follow system language".
class LocaleNotifier extends ChangeNotifier {
  static const _storageKey = 'app_locale';

  Locale? _locale;

  /// Current locale. Null = follow system language.
  Locale? get locale => _locale;

  /// Display name for the current language setting.
  String get displayName {
    if (_locale == null) return 'System';
    return switch (_locale!.languageCode) {
      'zh' => '中文',
      'en' => 'English',
      _ => _locale!.languageCode,
    };
  }

  /// Load saved locale from SharedPreferences on startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_storageKey);
    if (code != null && code.isNotEmpty) {
      _locale = Locale(code);
      _log.fine('Loaded saved locale: $code');
    }
  }

  /// Set locale and persist. Pass null to follow system language.
  Future<void> setLocale(Locale? locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_storageKey);
      _log.info('语言切换: 跟随系统');
    } else {
      await prefs.setString(_storageKey, locale.languageCode);
      _log.info('语言切换: ${locale.languageCode}');
    }
  }
}
