import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Builds the light and dark [ThemeData] from the token files.
///
/// Screens should not read raw Material colours; they read `context.colors`,
/// which resolves the [AppColors] extension installed here.
class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final TextTheme text = AppTypography.textTheme(
      primary: c.textPrimary,
      secondary: c.textSecondary,
    );

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onBrand,
      secondary: c.accent,
      onSecondary: c.onBrand,
      error: c.danger,
      onError: c.onBrand,
      surface: c.surface,
      onSurface: c.textPrimary,
      outline: c.border,
      shadow: c.shadow,
      // Material 3 tints elevated surfaces by default; HozaSend controls its
      // own surface colours, so the tint is switched off.
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[c],
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
        iconTheme: IconThemeData(color: c.textSecondary),
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: 22),
      dividerTheme: DividerThemeData(
        color: c.border,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceElevated,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.sm)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceMuted,
        hintStyle: text.bodyMedium?.copyWith(color: c.textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.primary, width: 1.6),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: HozaPageTransitionsBuilder(),
          TargetPlatform.windows: HozaPageTransitionsBuilder(),
          TargetPlatform.linux: HozaPageTransitionsBuilder(),
          TargetPlatform.macOS: HozaPageTransitionsBuilder(),
          TargetPlatform.iOS: HozaPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// One page transition for every platform: the arriving page fades and rises
/// while the page it covers steps back and dims.
///
/// The depth cue is what makes a screen change read as "on top of" rather than
/// "instead of", and it costs nothing while idle - both fades sit at opacity 1
/// until a route actually moves. Short enough that it never delays the user.
class HozaPageTransitionsBuilder extends PageTransitionsBuilder {
  const HozaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // "Remove animations" in the OS accessibility settings is a real request,
    // not a hint. Cross-fade only, so the screen still changes legibly.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return FadeTransition(opacity: animation, child: child);
    }

    final Animation<double> enter = CurvedAnimation(
      parent: animation,
      curve: Motion.standard,
      reverseCurve: Motion.exit,
    );
    final Animation<double> leave = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Motion.standard,
      reverseCurve: Motion.exit,
    );

    final Widget arriving = FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.028),
          end: Offset.zero,
        ).animate(enter),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(enter),
          child: child,
        ),
      ),
    );

    // Applied to the same subtree: while this page is the one being covered,
    // `secondaryAnimation` runs and these two pull it gently backwards.
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.62).animate(leave),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.975).animate(leave),
        child: arriving,
      ),
    );
  }
}

/// Shorthand accessors so widgets stay readable.
extension HozaThemeContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;

  TextTheme get text => Theme.of(this).textTheme;

  /// True once the window is wide enough to deserve a desktop layout.
  bool get isWide => MediaQuery.sizeOf(this).width >= Breakpoints.medium;

  /// Horizontal page padding for the current width.
  double get pagePadding => isWide ? Insets.pageDesktop : Insets.page;

  /// True when the platform asks for reduced motion. Every animation in the
  /// app checks this in one of two ways: decorative loops do not start, and
  /// state changes still happen but instantly.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// A motion token, collapsed to zero when motion is reduced. Used at the
  /// call site so no widget has to repeat the check.
  Duration motion(Duration duration) => reduceMotion ? Duration.zero : duration;
}
