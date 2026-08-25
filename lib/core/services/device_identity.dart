import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';

import '../models/hoza_device.dart';

/// Who this installation is on the network.
class DeviceIdentity {
  const DeviceIdentity._();

  /// Maximum length accepted for a device name. Long enough for "Rayan's S24
  /// Ultra", short enough to keep the beacon small and the UI from wrapping.
  static const int maxNameLength = 30;

  static DevicePlatform get platform {
    if (Platform.isAndroid) return DevicePlatform.android;
    if (Platform.isWindows) return DevicePlatform.windows;
    if (Platform.isIOS) return DevicePlatform.ios;
    if (Platform.isMacOS) return DevicePlatform.macos;
    if (Platform.isLinux) return DevicePlatform.linux;
    return DevicePlatform.unknown;
  }

  /// 32 hex characters from a cryptographic RNG, written once and reused
  /// forever, so renaming a device does not make it look like a new one.
  /// Hand-rolled rather than pulling in a uuid package for a single call.
  static String generateId() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 4; i++) {
      buffer.write(random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'));
    }
    return buffer.toString();
  }

  /// A sensible starting point for the name field: the phone model, or the PC
  /// name. Device info is a nicety, so any failure falls back rather than
  /// blocking first launch.
  static Future<String> suggestName() async {
    try {
      final DeviceInfoPlugin info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo android = await info.androidInfo;
        final String model = android.model.trim();
        if (model.isNotEmpty) return _trim(model);
      } else if (Platform.isWindows) {
        final WindowsDeviceInfo windows = await info.windowsInfo;
        final String name = windows.computerName.trim();
        if (name.isNotEmpty) return _trim(name);
      } else if (Platform.isIOS) {
        // The name from Settings - "Rayan's iPhone" - which is exactly what
        // the user expects other devices to call this one.
        final IosDeviceInfo ios = await info.iosInfo;
        final String name = ios.name.trim();
        if (name.isNotEmpty) return _trim(name);
      } else if (Platform.isMacOS) {
        // The name the user set in System Settings - "Rayan's MacBook Pro" -
        // rather than the host name, which is the same thing mangled into
        // "Rayans-MacBook-Pro.local".
        final MacOsDeviceInfo mac = await info.macOsInfo;
        final String name = mac.computerName.trim();
        if (name.isNotEmpty) return _trim(name);
      }
    } catch (_) {
      // Fall through to the host name, then to the platform label.
    }
    try {
      String host = Platform.localHostname.trim();
      // Bonjour hands back "something.local"; the suffix is noise in a device
      // list where every entry would carry it.
      if (host.endsWith('.local')) {
        host = host.substring(0, host.length - '.local'.length);
      }
      if (host.isNotEmpty && host != 'localhost') return _trim(host);
    } catch (_) {
      // Some sandboxes deny the host name; the platform label still works.
    }
    return platform.label;
  }

  static String _trim(String value) => value.length <= maxNameLength
      ? value
      : value.substring(0, maxNameLength);
}
