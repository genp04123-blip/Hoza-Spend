import 'package:flutter/material.dart';

import 'app/app.dart';
import 'data/local/history_repository.dart';
import 'core/services/notification_service.dart';
import 'data/local/preferences_service.dart';
import 'features/connection/connection_controller.dart';
import 'features/discovery/discovery_controller.dart';
import 'features/history/history_controller.dart';
import 'features/settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Everything stored is read before the first frame, so the app opens straight
  // into the right theme, the right screen, and a populated history.
  final PreferencesService preferences = await PreferencesService.create();

  final SettingsController settings = SettingsController(preferences);
  await settings.load();

  // Asks for the notification permission on Android 13+. Declining costs only
  // the alerts, so this never blocks startup.
  await NotificationService.initialize();

  final HistoryController history =
      HistoryController(HistoryRepository(preferences));
  await history.load();

  // Discovery and connection read their identity from settings on demand, so a
  // rename takes effect without restarting either.
  final DiscoveryController discovery = DiscoveryController(settings);
  final ConnectionController connection = ConnectionController(settings);

  runApp(
    HozaApp(
      settings: settings,
      discovery: discovery,
      connection: connection,
      history: history,
    ),
  );
}
