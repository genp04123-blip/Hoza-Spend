import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/log.dart';

/// Keeps Android's Wi-Fi radio doing what HozaSend needs it to do.
///
/// Two separate locks, for two separate problems:
///
/// * The **multicast lock** stops Wi-Fi power saving from dropping packets
///   that are not addressed to this device. Without it, discovery goes quiet
///   as soon as the screen dims - which is the exact moment a user puts the
///   phone down and expects to still be findable. Held while discovery runs.
///
/// * The **link lock** keeps the radio out of its power-saving duty cycle
///   while a session is live. Without it a long transfer with the screen off
///   slows to a crawl and can miss enough heartbeats to be declared dead,
///   which a user experiences as "large files always fail".
///
/// There is no Dart API for either, so this talks to a small handler in
/// MainActivity. Every call is best effort: discovery and transfers both work
/// with the screen on, so a failure here degrades the experience rather than
/// breaking it.
class WifiLockService {
  const WifiLockService._();

  static const MethodChannel _channel = MethodChannel('hozasend/wifi_lock');
  static const String _tag = 'Network';

  static bool get isSupported => Platform.isAndroid;

  static Future<void> acquire() => _invoke('acquire', 'multicast lock');

  static Future<void> release() => _invoke('release', 'multicast lock');

  /// Held for the lifetime of a session, not just the transfer inside it: the
  /// heartbeat that keeps the session alive is as vulnerable to a sleeping
  /// radio as the file bytes are.
  static Future<void> acquireLink() => _invoke('acquireLink', 'link lock');

  static Future<void> releaseLink() => _invoke('releaseLink', 'link lock');

  static Future<void> _invoke(String method, String what) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>(method);
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not $method $what: ${error.message}');
    } on MissingPluginException {
      // An older host build without the handler. Not worth surfacing.
    }
  }
}
