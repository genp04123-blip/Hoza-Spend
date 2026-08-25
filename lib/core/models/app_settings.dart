import 'package:flutter/material.dart' show ThemeMode;

/// Everything HozaSend remembers between launches.
///
/// Small on purpose: the guide is explicit that Settings must not grow into a
/// preferences dumping ground.
class AppSettings {
  const AppSettings({
    required this.deviceId,
    required this.deviceName,
    required this.themeMode,
    required this.autoAccept,
    required this.notificationsEnabled,
    required this.downloadPath,
    this.hasSeenIntro = false,
    this.hasPreparedFolder = false,
  });

  static const AppSettings empty = AppSettings(
    deviceId: '',
    deviceName: '',
    themeMode: ThemeMode.system,
    autoAccept: false,
    notificationsEnabled: true,
    downloadPath: null,
  );

  /// Stable per-installation id, generated once on first launch.
  final String deviceId;

  /// What other devices see in their nearby list.
  final String deviceName;

  final ThemeMode themeMode;

  /// Skip the incoming-file prompt. Off by default: silently accepting files
  /// from the network is exactly what the confirmation step exists to prevent.
  final bool autoAccept;

  final bool notificationsEnabled;

  /// Where received files are written. Null only before the first resolve.
  final String? downloadPath;

  /// Whether the how-it-works pages have been shown. Stored separately from
  /// [deviceName] so the intro can be replayed from Settings without the app
  /// thinking this is a fresh install.
  final bool hasSeenIntro;

  /// Whether the user has been shown where received files are saved. Asked
  /// once, on the first launch that reaches the home screen.
  final bool hasPreparedFolder;

  /// First launch is complete once the device has a name.
  bool get isOnboarded => deviceName.trim().isNotEmpty;

  AppSettings copyWith({
    String? deviceId,
    String? deviceName,
    ThemeMode? themeMode,
    bool? autoAccept,
    bool? notificationsEnabled,
    String? downloadPath,
    bool? hasSeenIntro,
    bool? hasPreparedFolder,
  }) {
    return AppSettings(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      themeMode: themeMode ?? this.themeMode,
      autoAccept: autoAccept ?? this.autoAccept,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      downloadPath: downloadPath ?? this.downloadPath,
      hasSeenIntro: hasSeenIntro ?? this.hasSeenIntro,
      hasPreparedFolder: hasPreparedFolder ?? this.hasPreparedFolder,
    );
  }
}
