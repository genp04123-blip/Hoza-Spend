import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Typed access to the small amount of state HozaSend persists.
///
/// Everything else in the app talks to this rather than to SharedPreferences
/// directly, so the key strings exist in exactly one place.
class PreferencesService {
  const PreferencesService._(this._prefs);

  final SharedPreferences _prefs;

  static Future<PreferencesService> create() async {
    return PreferencesService._(await SharedPreferences.getInstance());
  }

  static const String _kDeviceId = 'hoza.device_id';
  static const String _kDeviceName = 'hoza.device_name';
  static const String _kThemeMode = 'hoza.theme_mode';
  static const String _kAutoAccept = 'hoza.auto_accept';
  static const String _kNotifications = 'hoza.notifications';
  static const String _kDownloadPath = 'hoza.download_path';
  static const String _kHistory = 'hoza.history';
  static const String _kSeenIntro = 'hoza.seen_intro';
  static const String _kPreparedFolder = 'hoza.prepared_folder';

  String? get deviceId => _prefs.getString(_kDeviceId);
  Future<void> setDeviceId(String value) => _prefs.setString(_kDeviceId, value);

  String? get deviceName => _prefs.getString(_kDeviceName);
  Future<void> setDeviceName(String value) =>
      _prefs.setString(_kDeviceName, value);

  /// Stored by name rather than index so reordering the enum cannot silently
  /// change a user's saved choice.
  ThemeMode get themeMode {
    final String? stored = _prefs.getString(_kThemeMode);
    return ThemeMode.values.firstWhere(
      (ThemeMode mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode value) =>
      _prefs.setString(_kThemeMode, value.name);

  bool get autoAccept => _prefs.getBool(_kAutoAccept) ?? false;
  Future<void> setAutoAccept(bool value) =>
      _prefs.setBool(_kAutoAccept, value);

  bool get notificationsEnabled => _prefs.getBool(_kNotifications) ?? true;
  Future<void> setNotificationsEnabled(bool value) =>
      _prefs.setBool(_kNotifications, value);

  /// Null until the user picks one; the default is resolved at runtime so a
  /// stored path cannot go stale when the OS moves a folder.
  String? get downloadPath => _prefs.getString(_kDownloadPath);
  Future<void> setDownloadPath(String value) =>
      _prefs.setString(_kDownloadPath, value);

  bool get hasSeenIntro => _prefs.getBool(_kSeenIntro) ?? false;
  Future<void> setSeenIntro(bool value) => _prefs.setBool(_kSeenIntro, value);

  bool get hasPreparedFolder => _prefs.getBool(_kPreparedFolder) ?? false;
  Future<void> setPreparedFolder(bool value) =>
      _prefs.setBool(_kPreparedFolder, value);

  /// Transfer history as encoded JSON.
  List<String> get history => _prefs.getStringList(_kHistory) ?? <String>[];
  Future<void> setHistory(List<String> value) =>
      _prefs.setStringList(_kHistory, value);
}
