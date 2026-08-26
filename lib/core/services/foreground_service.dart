import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/log.dart';

/// Keeps the app running while a session is live and the user is elsewhere.
///
/// Android only, and it exists because the Wi-Fi locks do not go far enough.
/// Those keep the *radio* awake; nothing keeps the *process* awake. A few
/// minutes after the last activity stops, Android freezes the app's threads
/// and its sockets go with them - so a user who switches away mid-transfer to
/// answer a message comes back to a connection that died while they were gone.
/// On a small file nobody notices. On a large one it is the whole feature.
///
/// A foreground service is the sanctioned way to say "this process is doing
/// something the user asked for", and its notification is the honest price:
/// something is using their network and their battery, and it should be
/// visible and one tap away.
///
/// Every call is best effort. Android refuses to start one of these from the
/// background, and a session that begins while the app is off screen will be
/// refused - which costs the protection, not the transfer.
class ForegroundService {
  const ForegroundService._();

  static const MethodChannel _channel = MethodChannel('hozasend/session');

  static const String _tag = 'Session';

  /// Windows and macOS do not freeze a running process, and desktop users can
  /// see the window. This is a mobile problem with a mobile answer.
  static bool get isSupported => Platform.isAndroid;

  /// What was last sent, so a repeated progress tick does not cross the method
  /// channel for a notification that would look identical. Transfer progress
  /// arrives many times a second; the shade only redraws whole percent.
  static String? _lastTitle;
  static String? _lastText;
  static int _lastProgress = -2;

  static bool _visible = false;

  /// Set when Android turns the service down, which it does for the whole of
  /// a session rather than momentarily: the reason is always that the app was
  /// in the background when the session began, and that does not change until
  /// the next one. Without this, every progress tick would cross the channel
  /// to be refused again.
  static bool _refused = false;

  /// True while the notification is up. Only ever a local belief - Android may
  /// have refused - but enough to keep [hide] from crossing the channel for
  /// something that was never shown.
  static bool get isVisible => _visible;

  /// Raises the notification, or updates the one already there.
  ///
  /// [progress] is 0-100, or null for work with no measurable end: connected
  /// and idle, or waiting on the other user to accept. Those show a moving
  /// bar rather than one stuck at zero.
  static Future<void> show({
    required String title,
    required String text,
    int? progress,
  }) async {
    if (!isSupported || _refused) return;

    final int value = progress == null ? -1 : progress.clamp(0, 100);
    if (title == _lastTitle && text == _lastText && value == _lastProgress) {
      return;
    }
    _lastTitle = title;
    _lastText = text;
    _lastProgress = value;

    try {
      final bool? shown = await _channel.invokeMethod<bool>(
        'show',
        <String, Object?>{
          'title': title,
          'text': text,
          'progress': value,
        },
      );
      _visible = shown ?? false;
      if (!_visible) {
        _refused = true;
        Log.warn(_tag, 'Android refused the foreground service');
      }
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not show session notice: ${error.message}');
      _visible = false;
      _refused = true;
    } on MissingPluginException {
      // An older host build without the handler.
      _visible = false;
      _refused = true;
    }
  }

  static Future<void> hide() async {
    _lastTitle = null;
    _lastText = null;
    _lastProgress = -2;
    // Cleared here rather than on the next show, so the next session gets a
    // fresh attempt: it may well begin with the app on screen, where Android
    // allows what it just turned down.
    _refused = false;
    if (!isSupported || !_visible) return;
    _visible = false;

    try {
      await _channel.invokeMethod<bool>('hide');
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not clear session notice: ${error.message}');
    } on MissingPluginException {
      // Nothing to clear.
    }
  }
}
