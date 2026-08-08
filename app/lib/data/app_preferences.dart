import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._(this._preferences);

  static const _themeKey = 'appearance.theme_mode';
  static const _remindersKey = 'reminders.enabled';
  static const _museumAutoArchiveDaysKey = 'profiles.museum_auto_archive_days';

  final SharedPreferences _preferences;

  static Future<AppPreferences> load() async =>
      AppPreferences._(await SharedPreferences.getInstance());

  ThemeMode get themeMode => switch (_preferences.getString(_themeKey)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  bool get remindersEnabled => _preferences.getBool(_remindersKey) ?? true;

  /// `null` 表示永不自动归档；新安装默认在 Profile 服务到期 90 天后归档。
  int? get museumAutoArchiveDays {
    final stored = _preferences.getInt(_museumAutoArchiveDaysKey);
    if (stored == null) return 90;
    return stored < 0 ? null : stored;
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _preferences.setString(_themeKey, mode.name);

  Future<void> setRemindersEnabled(bool value) =>
      _preferences.setBool(_remindersKey, value);

  Future<void> setMuseumAutoArchiveDays(int? value) =>
      _preferences.setInt(_museumAutoArchiveDaysKey, value ?? -1);
}
