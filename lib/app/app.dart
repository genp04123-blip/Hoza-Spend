import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../features/connection/connection_controller.dart';
import '../features/discovery/discovery_controller.dart';
import '../features/history/history_controller.dart';
import '../features/selection/selection_controller.dart';
import '../features/settings/settings_controller.dart';
import '../features/transfer/transfer_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root of the application.
///
/// The controllers are built in `main` before the first frame, so the very
/// first paint already uses the stored theme and starts on the right screen -
/// no flash of the wrong mode, and no onboarding shown to a returning user.
class HozaApp extends StatelessWidget {
  const HozaApp({
    super.key,
    required this.settings,
    required this.discovery,
    required this.connection,
    required this.history,
  });

  final SettingsController settings;
  final DiscoveryController discovery;
  final ConnectionController connection;
  final HistoryController history;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<DiscoveryController>.value(value: discovery),
        ChangeNotifierProvider<ConnectionController>.value(value: connection),
        ChangeNotifierProvider<HistoryController>.value(value: history),
        // The only controller with no state worth keeping across a restart, so
        // it is created here rather than in main.
        ChangeNotifierProvider<SelectionController>(
          create: (BuildContext context) => SelectionController(),
        ),
        ChangeNotifierProvider<TransferController>(
          // Not lazy: an incoming transfer can start before any screen has
          // asked for this controller, and something has to be listening.
          lazy: false,
          create: (BuildContext context) => TransferController(
            context.read<ConnectionController>(),
            context.read<SettingsController>(),
            context.read<HistoryController>(),
          ),
        ),
      ],
      child: Consumer<SettingsController>(
        builder: (
          BuildContext context,
          SettingsController controller,
          Widget? child,
        ) {
          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            navigatorKey: AppRouter.navigatorKey,
            builder: (BuildContext context, Widget? child) =>
                _KeyboardShortcuts(child: child ?? const SizedBox.shrink()),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: controller.themeMode,
            // Always the splash. It runs the launch animation and then picks
            // the real entry screen - intro, device naming, or home - so that
            // decision lives in one place instead of being split between here
            // and the navigation that follows.
            initialRoute: AppRoutes.splash,
            onGenerateRoute: AppRouter.onGenerateRoute,
          );
        },
      ),
    );
  }
}

/// App-wide keys. Escape is what a desktop user reaches for to back out of a
/// screen, and without it the Windows build feels like a phone app in a window.
///
/// It routes through [AppRouter.navigatorKey] because this sits above the
/// Navigator in the tree. `maybePop` is deliberate: a screen that blocks
/// popping - the transfer screen mid-transfer - stays put.
class _KeyboardShortcuts extends StatelessWidget {
  const _KeyboardShortcuts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          AppRouter.navigatorKey.currentState?.maybePop();
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
