import 'dart:io';

// Narrowed on purpose: `package:flutter/widgets.dart` re-exports a `Priority`
// from the scheduler that collides with the notification one.
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/formatters.dart';
import '../utils/log.dart';

/// Android notifications for transfers.
///
/// Android only. Windows notifications would need an app registration and a
/// GUID for something a desktop user is already looking at; the transfer screen
/// is the notification there.
class NotificationService {
  const NotificationService._();

  static const String _tag = 'Notify';

  static const int _incomingId = 1;
  static const int _completedId = 2;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// Windows is excluded on purpose: notifications there need an app
  /// registration and a GUID for something a desktop user is already looking
  /// at. macOS needs neither, and its Notification Centre is where a Mac user
  /// expects a finished transfer to appear.
  static bool get isSupported =>
      Platform.isAndroid || Platform.isMacOS || Platform.isIOS;

  static const AndroidNotificationDetails _android =
      AndroidNotificationDetails(
    'transfers',
    'Transfers',
    channelDescription: 'Incoming and completed file transfers',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const DarwinNotificationDetails _darwin = DarwinNotificationDetails(
    presentAlert: true,
    presentBanner: true,
    presentSound: false,
  );

  static const NotificationDetails _details = NotificationDetails(
    android: _android,
    macOS: _darwin,
    iOS: _darwin,
  );

  /// Sets up the channel and asks for permission. Safe to call more than once.
  static Future<void> initialize() async {
    if (!isSupported || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Asked for explicitly below instead, so the prompt appears at a
          // moment the user can connect to something rather than the instant
          // the app opens.
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );

      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: false);
      } else {
        await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: false);
      }
      _ready = true;
    } catch (error) {
      Log.warn(_tag, 'Could not set up notifications: $error');
    }
  }

  /// True when the app is not on screen. A notification for something the user
  /// is already watching is noise, so nothing is posted while resumed.
  static bool get _isBackgrounded =>
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;

  static Future<void> incoming({
    required String deviceName,
    required int fileCount,
    required int totalBytes,
  }) {
    return _show(
      id: _incomingId,
      title: fileCount == 1 ? 'Incoming file' : 'Incoming $fileCount files',
      body: 'From $deviceName - ${Formatters.bytes(totalBytes)}',
    );
  }

  static Future<void> completed({
    required bool sent,
    required String deviceName,
    required int fileCount,
  }) {
    final String noun = fileCount == 1 ? 'file' : 'files';
    return _show(
      id: _completedId,
      title: sent ? 'Sent successfully' : 'Received $fileCount $noun',
      body: sent ? 'Delivered to $deviceName' : 'From $deviceName',
    );
  }

  static Future<void> failed({required String reason}) {
    return _show(id: _completedId, title: 'Transfer failed', body: reason);
  }

  /// Clears the incoming notice once the prompt has been answered, so a stale
  /// alert cannot outlive the thing it was about.
  static Future<void> clearIncoming() async {
    if (!isSupported || !_ready) return;
    try {
      await _plugin.cancel(id: _incomingId);
    } catch (_) {
      // Nothing useful to do if the shade refuses.
    }
  }

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!isSupported || !_ready || !_isBackgrounded) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        // Notification text is a summary, never file contents or a path.
        body: body.split('\n').first,
        notificationDetails: _details,
      );
    } catch (error) {
      Log.warn(_tag, 'Could not post notification: $error');
    }
  }
}
