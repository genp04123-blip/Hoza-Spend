import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../features/connection/connection_controller.dart';
import '../features/discovery/discovery_controller.dart';
import '../features/history/history_controller.dart';
import '../core/services/share_intake_service.dart';
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
      child: _ShareHost(
        child: Consumer<SettingsController>(
          builder: (BuildContext context, SettingsController controller, Widget? child) {
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
              // Lets the share handler above see which screen is on top.
              navigatorObservers: <NavigatorObserver>[AppRouteObserver()],
            );
          },
        ),
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

/// Turns files handed over by another app into a queued send.
///
/// Sits between the providers and the app because the two things it needs are
/// on either side of it: the selection to put files in, and the navigator to
/// take the user to them.
///
/// The rule it follows is the one the user has already stated by sharing: they
/// picked these files and they picked this app, so the files are queued and the
/// send screen opens. What it will not do is interrupt - a share that lands
/// while the send screen is already up, or mid-transfer, only adds to the
/// queue.
class _ShareHost extends StatefulWidget {
  const _ShareHost({required this.child});

  final Widget child;

  @override
  State<_ShareHost> createState() => _ShareHostState();
}

class _ShareHostState extends State<_ShareHost> {
  @override
  void initState() {
    super.initState();
    ShareIntake.instance.listen(_onShared);
  }

  @override
  void dispose() {
    ShareIntake.instance.stopListening(_onShared);
    super.dispose();
  }

  Future<void> _onShared(List<String> paths) async {
    if (!mounted) return;
    final SelectionController selection = context.read<SelectionController>();
    final SettingsController settings = context.read<SettingsController>();

    // Folders are expanded on the way in, exactly as they are for a drop, so
    // "Send to HozaSend" on a folder means its contents.
    await selection.addPaths(paths);
    if (!mounted || selection.isEmpty) return;

    // Someone still being asked for a device name has not finished setting the
    // app up. The files stay queued either way: Send will already be holding
    // them by the time they get there.
    if (!settings.isOnboarded) return;

    final String? current = AppRouteObserver.current;
    if (current == AppRoutes.selection || current == AppRoutes.transfer) return;

    AppRouter.navigatorKey.currentState?.pushNamed(AppRoutes.selection);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
