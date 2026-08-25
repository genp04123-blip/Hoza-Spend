import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';
import '../../core/services/device_identity.dart';
import '../../core/services/file_picker_service.dart';
import '../../data/local/preferences_service.dart';
import '../../data/local/storage_service.dart';

/// Owns [AppSettings] and is the only writer of it.
///
/// Deliberately the single source of truth for the device identity too: the
/// discovery layer in Section 3 reads its id and name from here rather than
/// keeping a second copy that could drift after a rename.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs);

  final PreferencesService _prefs;

  AppSettings _settings = AppSettings.empty;
  AppSettings get settings => _settings;

  ThemeMode get themeMode => _settings.themeMode;
  String get deviceId => _settings.deviceId;
  String get deviceName => _settings.deviceName;
  bool get isOnboarded => _settings.isOnboarded;
  String? get downloadPath => _settings.downloadPath;

  /// Reads stored values and mints a device id if this is the first launch.
  /// Called before `runApp` so the first frame already has the right theme and
  /// the right starting route - no flash of the wrong screen.
  Future<void> load() async {
    String id = _prefs.deviceId ?? '';
    if (id.isEmpty) {
      id = DeviceIdentity.generateId();
      await _prefs.setDeviceId(id);
    }

    // The default is resolved fresh each launch instead of being persisted, so
    // it cannot go stale if the OS moves the folder.
    final String path =
        _prefs.downloadPath ?? await StorageService.defaultDownloadDirectory();

    _settings = AppSettings(
      deviceId: id,
      deviceName: _prefs.deviceName ?? '',
      themeMode: _prefs.themeMode,
      autoAccept: _prefs.autoAccept,
      notificationsEnabled: _prefs.notificationsEnabled,
      downloadPath: path,
      hasSeenIntro: _prefs.hasSeenIntro,
      hasPreparedFolder: _prefs.hasPreparedFolder,
    );
    notifyListeners();
  }

  bool get hasSeenIntro => _settings.hasSeenIntro;

  bool get hasPreparedFolder => _settings.hasPreparedFolder;

  Future<void> markFolderPrepared() async {
    if (_settings.hasPreparedFolder) return;
    await _prefs.setPreparedFolder(true);
    _settings = _settings.copyWith(hasPreparedFolder: true);
    notifyListeners();
  }

  Future<void> markIntroSeen() async {
    if (_settings.hasSeenIntro) return;
    await _prefs.setSeenIntro(true);
    _settings = _settings.copyWith(hasSeenIntro: true);
    notifyListeners();
  }

  Future<void> setDeviceName(String value) async {
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _settings.deviceName) return;
    final String capped = trimmed.length > DeviceIdentity.maxNameLength
        ? trimmed.substring(0, DeviceIdentity.maxNameLength)
        : trimmed;
    await _prefs.setDeviceName(capped);
    _settings = _settings.copyWith(deviceName: capped);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (value == _settings.themeMode) return;
    await _prefs.setThemeMode(value);
    _settings = _settings.copyWith(themeMode: value);
    notifyListeners();
  }

  Future<void> setAutoAccept(bool value) async {
    if (value == _settings.autoAccept) return;
    await _prefs.setAutoAccept(value);
    _settings = _settings.copyWith(autoAccept: value);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    if (value == _settings.notificationsEnabled) return;
    await _prefs.setNotificationsEnabled(value);
    _settings = _settings.copyWith(notificationsEnabled: value);
    notifyListeners();
  }

  Future<void> setDownloadPath(String value) async {
    if (value.isEmpty || value == _settings.downloadPath) return;
    await _prefs.setDownloadPath(value);
    _settings = _settings.copyWith(downloadPath: value);
    notifyListeners();
  }

  /// True where the user can pick a download folder at all.
  ///
  /// Android is excluded on purpose: its picker returns a storage-access URI
  /// that `dart:io` cannot write to, so offering the button there would give a
  /// choice that silently does nothing.
  bool get canChooseDownloadPath => FilePickerService.supportsFolders;

  /// Opens the folder picker. Does nothing if the user cancels.
  Future<void> chooseDownloadPath() async {
    final String? chosen = await FilePickerService.pickDirectory();
    if (chosen == null) return;
    await setDownloadPath(chosen);
  }
}
