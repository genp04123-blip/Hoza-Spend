import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/log.dart';

/// Keeps Android delivering broadcast packets while discovery runs.
///
/// Without a multicast lock, Android's Wi-Fi power saving drops packets that
/// are not addressed to this device as soon as the screen dims - which is the
/// exact moment a user puts the phone down and expects to still be findable.
/// There is no Dart API for it, so this talks to a small handler in
/// MainActivity.
///
/// Every call is best effort. Discovery already works with the screen on, so a
/// failure here degrades the experience rather than breaking it.
class WifiLockService {
  const WifiLockService._();

  static const MethodChannel _channel = MethodChannel('hozasend/wifi_lock');
  static const String _tag = 'Network';

  static bool get isSupported => Platform.isAndroid;

  static Future<void> acquire() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('acquire');
      Log.info(_tag, 'Multicast lock acquired');
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not acquire multicast lock: ${error.message}');
    } on MissingPluginException {
      // An older host build without the handler. Not worth surfacing.
    }
  }

  static Future<void> release() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('release');
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not release multicast lock: ${error.message}');
    } on MissingPluginException {
      // Nothing to release.
    }
  }
}
