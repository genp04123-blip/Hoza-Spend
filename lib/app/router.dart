import 'package:flutter/material.dart';

import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/intro_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/receive/receive_screen.dart';
import '../features/selection/selection_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/transfer/transfer_screen.dart';

/// Named routes. Constants so a typo is a compile error rather than a runtime
/// one, and so deep links have a single place to live later.
class AppRoutes {
  const AppRoutes._();

  /// Every launch starts here. The splash decides which of the three entry
  /// screens actually opens.
  static const String splash = '/';

  static const String home = '/home';
  static const String intro = '/intro';
  static const String onboarding = '/onboarding';
  static const String settings = '/settings';
  static const String selection = '/send';
  static const String receive = '/receive';
  static const String transfer = '/transfer';
  static const String history = '/history';
}

class AppRouter {
  const AppRouter._();

  /// Lets code above the Navigator - the keyboard handler in particular - still
  /// reach it.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Everything goes through [hozaRoute] so page transitions stay identical
  /// across the app instead of being set per navigation call.
  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    final Widget page = switch (routeSettings.name) {
      AppRoutes.splash => const SplashScreen(),
      AppRoutes.home => const HomeScreen(),
      AppRoutes.intro => const IntroScreen(),
      AppRoutes.onboarding => const OnboardingScreen(),
      AppRoutes.settings => const SettingsScreen(),
      AppRoutes.selection => const SelectionScreen(),
      AppRoutes.receive => const ReceiveScreen(),
      AppRoutes.transfer => const TransferScreen(),
      AppRoutes.history => const HistoryScreen(),
      _ => const HomeScreen(),
    };
    return hozaRoute<void>(page, routeSettings);
  }
}

/// The app's standard page route. The transition itself lives in
/// `HozaPageTransitionsBuilder` in the theme; this only carries the settings.
PageRoute<T> hozaRoute<T>(Widget page, [RouteSettings? settings]) {
  return MaterialPageRoute<T>(
    builder: (BuildContext context) => page,
    settings: settings,
  );
}
