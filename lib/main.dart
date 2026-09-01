import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/file_picker_service.dart';
import 'core/services/share_intake_service.dart';
import 'data/local/history_repository.dart';
import 'core/services/notification_service.dart';
import 'data/local/preferences_service.dart';
import 'features/connection/connection_controller.dart';
import 'features/discovery/discovery_controller.dart';
import 'features/history/history_controller.dart';
import 'features/settings/settings_controller.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read before anything else. On Windows a share arrives as the command line
  // this process was started with, and on Android as the intent that launched
  // the activity; both are waiting the moment the app exists.
  ShareIntake.instance.start(arguments);

  // Everything stored is read before the first frame, so the app opens straight
  // into the right theme, the right screen, and a populated history.
  final PreferencesService preferences = await PreferencesService.create();

  final SettingsController settings = SettingsController(preferences);
  await settings.load();

  // Asks for the notification permission on Android 13+. Declining costs only
  // the alerts, so this never blocks startup.
  await NotificationService.initialize();

  // Working copies left by the phone pickers, from previous runs. Startup is
  // the one moment nothing is queued and nothing is being read, so it is the
  // only safe moment to remove them - and without it the app's storage grows
  // by the size of everything ever sent from it. Never awaited: it is
  // housekeeping, and the first frame must not wait on a directory walk.
  unawaited(FilePickerService.clearWorkingCopies());

  final HistoryController history =
      HistoryController(HistoryRepository(preferences));
  await history.load();

  // Discovery and connection read their identity from settings on demand, so a
  // rename takes effect without restarting either.
  final DiscoveryController discovery = DiscoveryController(settings);
  final ConnectionController connection = ConnectionController(settings);

  // The one thing discovery needs to know about connections: whether it is
  // safe to go quiet when the app is backgrounded. Announcing goodbye during a
  // live transfer would take this device off the other user's screen while it
  // is still sending them a file.
  // Any live session counts, not just the one the send screen happens to be
  // pointed at: going quiet because *that* one ended would take this device
  // off the screen of the two it is still connected to.
  discovery.keepRunningWhile = () => connection.connectedCount > 0;

  runApp(
    HozaApp(
      settings: settings,
      discovery: discovery,
      connection: connection,
      history: history,
    ),
  );
}
