import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/log.dart';

/// The system screens HozaSend ever needs the user to visit.
enum NetworkSetting {
  /// Join a Wi-Fi network.
  wifi,

  /// Turn this device into one.
  hotspot,

  /// Let HozaSend through the firewall.
  ///
  /// Only ever offered on the desktops that have one in the way. A dismissed
  /// Windows Firewall prompt on first launch blocks every inbound packet for
  /// good, and the app looks broken for ever after with nothing on screen to
  /// say why - this is the shortcut to the one screen that fixes it.
  firewall;

  String get label => switch (this) {
        NetworkSetting.wifi => 'Wi-Fi',
        NetworkSetting.hotspot => 'Hotspot',
        NetworkSetting.firewall => 'Firewall',
      };
}

/// Opens the operating system's network screens.
///
/// HozaSend cannot switch Wi-Fi on or open a firewall port by itself - no
/// platform has let an app do either without being a system app for years, and
/// it should not: turning a stranger's radio on, or punching a hole in their
/// firewall, is not an app's decision. What it can do is take the user
/// straight to the screen where they decide, which is the entire distance
/// between "connect both devices to the same network" as an instruction and as
/// a button.
///
/// No package behind it. Android needs an intent, which the app already has a
/// method channel for; Windows takes a URI or a control panel applet; macOS
/// goes through NSWorkspace because the App Sandbox blocks a sandboxed process
/// from driving LaunchServices.
class NetworkSettingsService {
  const NetworkSettingsService._();

  static const MethodChannel _channel =
      MethodChannel('hozasend/system_settings');

  static const String _tag = 'Network';

  /// Whether [setting] can be reached on this platform.
  ///
  /// iOS is excluded from all of them on purpose: the URL that opens Wi-Fi
  /// settings there is private API, and shipping it is how an app gets
  /// rejected. Linux has no one answer - every desktop environment puts
  /// network settings somewhere different - so it is left alone rather than
  /// guessed at. Android has no user-facing firewall to send anyone to.
  static bool supports(NetworkSetting setting) {
    return switch (setting) {
      NetworkSetting.wifi ||
      NetworkSetting.hotspot =>
        Platform.isAndroid || Platform.isWindows || Platform.isMacOS,
      NetworkSetting.firewall => Platform.isWindows || Platform.isMacOS,
    };
  }

  /// Opens [setting]. Returns false if the screen could not be reached, which
  /// the caller turns into a word to the user rather than a silent no-op.
  static Future<bool> open(NetworkSetting setting) async {
    if (!supports(setting)) return false;
    if (Platform.isWindows) return _openOnWindows(setting);
    return _openOverChannel(setting);
  }

  static Future<bool> _openOverChannel(NetworkSetting setting) async {
    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        switch (setting) {
          NetworkSetting.wifi => 'openWifi',
          NetworkSetting.hotspot => 'openHotspot',
          NetworkSetting.firewall => 'openFirewall',
        },
      );
      return opened ?? false;
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not open ${setting.name}: ${error.message}');
      return false;
    } on MissingPluginException {
      // An older host build without the handler.
      return false;
    }
  }

  /// Windows exposes these as things the shell already knows how to open, so
  /// this needs no native code at all.
  ///
  /// Settings URIs go to Explorer rather than to `cmd /c start`, which would
  /// flash a console window on every press. The firewall is the odd one out:
  /// `windowsdefender://network` lands on the Windows Security page, and where
  /// that is disabled or missing the classic applet is still there, and it is
  /// the one with "Allow an app through firewall" on it.
  static Future<bool> _openOnWindows(NetworkSetting setting) async {
    final List<(String, List<String>)> candidates = switch (setting) {
      NetworkSetting.wifi => <(String, List<String>)>[
          ('explorer.exe', <String>['ms-settings:network-wifi']),
        ],
      NetworkSetting.hotspot => <(String, List<String>)>[
          ('explorer.exe', <String>['ms-settings:network-mobilehotspot']),
        ],
      NetworkSetting.firewall => <(String, List<String>)>[
          ('explorer.exe', <String>['windowsdefender://network']),
          ('control.exe', <String>['firewall.cpl']),
        ],
    };

    for (final (String executable, List<String> arguments) in candidates) {
      try {
        await Process.run(executable, arguments);
        // Explorer reports a non-zero exit code even when it hands the URI
        // over successfully, so its result says nothing worth reading. Only a
        // failure to launch it at all is a real failure.
        return true;
      } catch (error) {
        Log.warn(_tag, 'Could not run $executable: $error');
      }
    }
    return false;
  }
}
