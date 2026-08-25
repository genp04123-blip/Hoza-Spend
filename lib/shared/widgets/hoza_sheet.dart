import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// The container every modal in HozaSend sits in.
///
/// A floating card rather than a sheet welded to the bottom edge: the same
/// shape reads correctly on a phone and centred in a desktop window, so
/// Windows does not inherit a stretched mobile pattern.
class HozaSheet extends StatelessWidget {
  const HozaSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    // The route already slides the sheet up; this makes the card itself
    // settle into place instead of arriving at full size, which is what a
    // centred card needs to read as "opened" rather than "pushed in".
    final Animation<double>? route = ModalRoute.of(context)?.animation;

    return SafeArea(
      child: Padding(
        // Lifts the card clear of an open keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _Entrance(
              route: route,
              child: Container(
                margin: const EdgeInsets.all(Insets.md),
                padding: const EdgeInsets.all(Insets.xl),
                decoration: BoxDecoration(
                  color: c.surfaceElevated,
                  borderRadius: BorderRadius.circular(Radii.xl),
                  border: Border.all(color: c.border),
                  boxShadow: c.liftedShadow,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scales and fades the sheet card with its own route.
///
/// Driven straight off the route animation rather than a controller of its
/// own, so dismissing plays the same motion backwards and an interrupted
/// gesture never leaves the card mid-scale.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.route, required this.child});

  final Animation<double>? route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (route == null || context.reduceMotion) return child;
    final Animation<double> curved =
        route!.drive(CurveTween(curve: Motion.emphasized));
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

/// A round tinted badge behind an icon. Used for the outcome of a modal:
/// success, failure, incoming.
class SheetBadge extends StatelessWidget {
  const SheetBadge({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    this.animate = false,
  });

  final IconData icon;
  final Color color;
  final Color background;

  /// Scales in once on first build. Reserved for the success moment.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final Widget badge = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 36, color: color),
    );

    if (!animate || context.reduceMotion) return badge;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.7, end: 1),
      duration: Motion.slow,
      curve: Motion.emphasized,
      builder: (BuildContext context, double value, Widget? child) =>
          Transform.scale(scale: value, child: child),
      child: badge,
    );
  }
}
